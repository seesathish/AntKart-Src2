using AK.Notification.Application.Channels;
using AK.Notification.Domain.Enums;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MimeKit;

namespace AK.Notification.Infrastructure.Channels;

// Email delivery channel using MailKit (a cross-platform .NET SMTP client).
//
// Local dev:   Mailhog SMTP trap on port 1025 — emails are captured and viewable at http://localhost:8025
//              No real emails are sent; no credentials required (Username left empty skips auth).
// Production:  Gmail SMTP via antkartadmin@gmail.com — set EmailSettings__Password env var with app password.
//
// Authentication is optional — if Username is empty (Mailhog), authentication is skipped entirely.
internal sealed class EmailNotificationChannel(
    IOptions<EmailSettings> options,
    ILogger<EmailNotificationChannel> logger)
    : INotificationChannel
{
    // This property tells INotificationChannelResolver which channel type this class handles.
    public NotificationChannel Channel => NotificationChannel.Email;

    public async Task SendAsync(NotificationMessage message, CancellationToken ct = default)
    {
        var settings = options.Value;

        // MimeMessage is the MailKit email builder — similar to System.Net.Mail.MailMessage
        // but more standards-compliant and with better async support.
        var email = new MimeMessage();
        email.From.Add(new MailboxAddress(settings.DisplayName, settings.From));
        email.To.Add(MailboxAddress.Parse(message.RecipientAddress));
        email.Subject = message.Subject ?? string.Empty;

        // Plain text body — extend to multipart/alternative here to add HTML support.
        email.Body = new TextPart("plain") { Text = message.Body };

        // SmtpClient is created per message (not reused) so it's properly disposed
        // and connection state doesn't leak between notifications.
        // Port 465 = implicit SSL (SslOnConnect); port 587 = STARTTLS; port 1025 (Mailhog) = plain.
        var socketOptions = settings.EnableSsl
            ? (settings.Port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls)
            : SecureSocketOptions.None;

        using var smtp = new SmtpClient();
        await smtp.ConnectAsync(settings.Host, settings.Port, socketOptions, ct);

        // Skip authentication for local Mailhog (no username/password configured).
        if (!string.IsNullOrEmpty(settings.Username) && !string.IsNullOrEmpty(settings.Password))
            await smtp.AuthenticateAsync(settings.Username, settings.Password, ct);

        await smtp.SendAsync(email, ct);

        // Disconnect cleanly — true = send QUIT command (graceful), false = just close socket.
        await smtp.DisconnectAsync(true, ct);

        logger.LogInformation("Email sent to {Recipient} with subject '{Subject}'", message.RecipientAddress, message.Subject);
    }
}
