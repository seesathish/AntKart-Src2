using AK.BuildingBlocks.Messaging;
using AK.Notification.Application.Channels;
using AK.Notification.Application.Repositories;
using AK.Notification.Application.Templates;
using AK.Notification.Application.Consumers;
using AK.Notification.Infrastructure.Channels;
using AK.Notification.Infrastructure.Persistence;
using AK.Notification.Infrastructure.Persistence.Repositories;
using AK.Notification.Infrastructure.Services;
using AK.Notification.Infrastructure.Templates;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AK.Notification.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connStr = configuration.GetConnectionString("Postgres")
            ?? throw new InvalidOperationException("Connection string 'Postgres' is missing.");

        services.AddDbContext<NotificationsDbContext>(opts =>
            opts.UseNpgsql(connStr));

        services.AddScoped<INotificationRepository, NotificationRepository>();

        services.AddScoped<INotificationChannel, EmailNotificationChannel>();
        services.AddScoped<INotificationChannel, SmsNotificationChannel>();
        services.AddScoped<INotificationChannel, WhatsAppNotificationChannel>();

        services.AddScoped<INotificationChannelResolver, NotificationChannelResolver>();
        services.AddScoped<INotificationTemplateRenderer, NotificationTemplateRenderer>();

        services.AddHostedService<NotificationCleanupService>();

        services.Configure<EmailSettings>(configuration.GetSection("EmailSettings"));
        services.Configure<NotificationSettings>(configuration.GetSection("NotificationSettings"));

        services.AddServiceBusMassTransit(configuration, "notification", cfg =>
        {
            cfg.AddConsumer<UserRegisteredConsumer>();
            cfg.AddConsumer<OrderCreatedConsumer>();
            cfg.AddConsumer<OrderConfirmedConsumer>();
            cfg.AddConsumer<OrderCancelledConsumer>();
            cfg.AddConsumer<PaymentSucceededConsumer>();
            cfg.AddConsumer<PaymentFailedConsumer>();
        });

        return services;
    }
}
