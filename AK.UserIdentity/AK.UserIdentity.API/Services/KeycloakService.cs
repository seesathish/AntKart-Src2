using AK.BuildingBlocks.Messaging.IntegrationEvents;
using AK.UserIdentity.API.DTOs;
using MassTransit;
using Microsoft.Extensions.Options;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace AK.UserIdentity.API.Services;

// Entra ID identity proxy — all Entra and Microsoft Graph HTTP calls go through this service.
// Wire protocol:
//   Login / Refresh  →  Entra token endpoint (ROPC / refresh_token grant)
//   Register         →  Microsoft Graph API POST /users (app-level credentials)
//   GetUserInfo      →  JWT payload parsed locally (no network call needed — token already validated)
public sealed class EntraIdService(
    IHttpClientFactory httpClientFactory,
    IOptions<EntraIdSettings> settings,
    IPublishEndpoint publisher) : IIdentityService
{
    private readonly EntraIdSettings _s = settings.Value;
    private const string ClientName    = "entra-id";
    private const string GraphUsers    = "https://graph.microsoft.com/v1.0/users";

    private string TokenUrl => $"https://login.microsoftonline.com/{_s.TenantId}/oauth2/v2.0/token";
    private string ApiScope => $"openid profile email offline_access api://{_s.ClientId}/access_as_user";

    // Resource Owner Password Credentials (ROPC) grant — exchanges username + password for JWT tokens.
    // ROPC is only safe server-side: credentials never travel from browser to Entra; they go to
    // our server first, which then forwards them to Entra's token endpoint.
    // Scope includes offline_access to request a refresh token alongside the access token.
    public async Task<TokenResponse> LoginAsync(string username, string password, CancellationToken ct = default)
    {
        var client = httpClientFactory.CreateClient(ClientName);

        var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"]    = "password",
            ["client_id"]     = _s.ClientId,
            ["client_secret"] = _s.ClientSecret,
            ["username"]      = username,
            ["password"]      = password,
            ["scope"]         = ApiScope
        });

        var response = await client.PostAsync(TokenUrl, content, ct);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync(ct);
            throw new UnauthorizedAccessException($"Login failed: {error}");
        }

        return ParseTokenResponse(await response.Content.ReadAsStringAsync(ct));
    }

    // Registration flow:
    //   1. Acquire an app-level token (client_credentials grant) to call Microsoft Graph
    //   2. POST /v1.0/users to create the Entra ID user account
    //   3. POST /v1.0/users/{id}/appRoleAssignments to assign the "user" app role
    //   4. Publish UserRegisteredIntegrationEvent → AK.Notification sends welcome email
    //
    // Graph API permissions required on the AntKart-API app registration:
    //   User.ReadWrite.All (application)
    //   AppRoleAssignment.ReadWrite.All (application)
    public async Task RegisterAsync(RegisterRequest request, CancellationToken ct = default)
    {
        var appToken = await GetAppTokenAsync(ct);
        var client = httpClientFactory.CreateClient(ClientName);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", appToken);

        // Entra requires UPN in format: alias@tenantdomain.onmicrosoft.com
        var mailNickname = request.Username.Replace(" ", "").ToLowerInvariant();
        var upn = $"{mailNickname}@{_s.TenantDomain}";

        var userPayload = new
        {
            accountEnabled        = true,
            displayName           = $"{request.FirstName} {request.LastName}".Trim(),
            givenName             = request.FirstName,
            surname               = request.LastName,
            mail                  = request.Email,
            mailNickname,
            userPrincipalName     = upn,
            passwordProfile       = new { forceChangePasswordNextSignIn = false, password = request.Password }
        };

        var httpContent = new StringContent(JsonSerializer.Serialize(userPayload), Encoding.UTF8, "application/json");
        var response = await client.PostAsync(GraphUsers, httpContent, ct);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync(ct);
            if (response.StatusCode == System.Net.HttpStatusCode.BadRequest &&
                error.Contains("userPrincipalName", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("User already exists.");
            throw new InvalidOperationException($"Registration failed: {error}");
        }

        var created = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(created);
        var userId = doc.RootElement.GetProperty("id").GetString()!;

        await AssignUserRoleAsync(userId, appToken, client, ct);

        await publisher.Publish(new UserRegisteredIntegrationEvent(
            userId,
            request.Email,
            $"{request.FirstName} {request.LastName}".Trim()), ct);
    }

    public async Task<TokenResponse> RefreshTokenAsync(string refreshToken, CancellationToken ct = default)
    {
        var client = httpClientFactory.CreateClient(ClientName);

        var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"]    = "refresh_token",
            ["client_id"]     = _s.ClientId,
            ["client_secret"] = _s.ClientSecret,
            ["refresh_token"] = refreshToken,
            ["scope"]         = ApiScope
        });

        var response = await client.PostAsync(TokenUrl, content, ct);

        if (!response.IsSuccessStatusCode)
            throw new UnauthorizedAccessException("Token refresh failed.");

        return ParseTokenResponse(await response.Content.ReadAsStringAsync(ct));
    }

    // Parses the JWT payload locally — no network call needed.
    // The token is already validated by the JWT Bearer middleware before this endpoint is called.
    // Roles come from the 'roles' claim (Entra app roles defined in the app registration).
    public Task<UserInfoResponse> GetUserInfoAsync(string accessToken, CancellationToken ct = default)
    {
        var parts = accessToken.Split('.');
        if (parts.Length != 3)
            throw new UnauthorizedAccessException("Invalid token format.");

        // Base64url decode the payload segment (pad to a multiple of 4 for standard base64).
        var padding = (4 - parts[1].Length % 4) % 4;
        var payloadBytes = Convert.FromBase64String(parts[1] + new string('=', padding));
        var payloadJson = Encoding.UTF8.GetString(payloadBytes);

        using var doc = JsonDocument.Parse(payloadJson);
        var root = doc.RootElement;

        var userId    = root.TryGetProperty("oid",              out var oid) ? oid.GetString()! : string.Empty;
        var email     = root.TryGetProperty("email",            out var em)  ? em.GetString()!  : string.Empty;
        var firstName = root.TryGetProperty("given_name",       out var gn)  ? gn.GetString()!  : string.Empty;
        var lastName  = root.TryGetProperty("family_name",      out var fn)  ? fn.GetString()!  : string.Empty;

        string username;
        if (root.TryGetProperty("preferred_username", out var un))
            username = un.GetString()!;
        else
            username = email;

        var roles = new List<string>();
        if (root.TryGetProperty("roles", out var rolesEl))
            foreach (var r in rolesEl.EnumerateArray())
                if (r.GetString() is { } rv) roles.Add(rv);

        return Task.FromResult(new UserInfoResponse(userId, username, email, firstName, lastName, roles));
    }

    // Client credentials grant — obtains an app-level token for Microsoft Graph API calls.
    // Scope https://graph.microsoft.com/.default requests all app permissions granted to this app.
    private async Task<string> GetAppTokenAsync(CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(ClientName);

        var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"]    = "client_credentials",
            ["client_id"]     = _s.ClientId,
            ["client_secret"] = _s.ClientSecret,
            ["scope"]         = "https://graph.microsoft.com/.default"
        });

        var response = await client.PostAsync(TokenUrl, content, ct);
        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }

    // Assigns the "user" app role to a newly registered user via Graph appRoleAssignments.
    // The assignment requires: principalId (user OID), resourceId (API's service principal OID),
    // and appRoleId (the GUID of the "user" role defined in the app registration).
    private async Task AssignUserRoleAsync(string userId, string appToken, HttpClient client, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_s.ApiObjectId) || string.IsNullOrEmpty(_s.UserRoleId)) return;

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", appToken);
        var assignUrl = $"https://graph.microsoft.com/v1.0/users/{userId}/appRoleAssignments";
        var body = JsonSerializer.Serialize(new
        {
            principalId = userId,
            resourceId  = _s.ApiObjectId,
            appRoleId   = _s.UserRoleId
        });
        await client.PostAsync(assignUrl, new StringContent(body, Encoding.UTF8, "application/json"), ct);
    }

    private static TokenResponse ParseTokenResponse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        return new TokenResponse(
            root.GetProperty("access_token").GetString()!,
            root.TryGetProperty("refresh_token", out var rt) ? rt.GetString()! : string.Empty,
            root.GetProperty("expires_in").GetInt32(),
            root.GetProperty("token_type").GetString()!);
    }
}
