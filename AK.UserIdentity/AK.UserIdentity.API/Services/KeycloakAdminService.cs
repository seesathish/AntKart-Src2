using AK.UserIdentity.API.DTOs;
using Microsoft.Extensions.Options;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace AK.UserIdentity.API.Services;

// Wraps Microsoft Graph API admin operations: list users, get app token, assign app roles.
// Uses IHttpClientFactory so connections are pooled — do not store HttpClient as a field.
public sealed class EntraIdAdminService(
    IHttpClientFactory httpClientFactory,
    IOptions<EntraIdSettings> settings) : IIdentityAdminService
{
    private readonly EntraIdSettings _s = settings.Value;
    private const string ClientName  = "entra-id";
    private const string GraphBase   = "https://graph.microsoft.com/v1.0";
    private const string GraphScope  = "https://graph.microsoft.com/.default";

    private string TokenUrl => $"https://login.microsoftonline.com/{_s.TenantId}/oauth2/v2.0/token";

    // Client credentials grant — obtains a short-lived app token with
    // User.Read.All + AppRoleAssignment.ReadWrite.All Graph permissions.
    public async Task<string> GetAdminTokenAsync(CancellationToken ct = default)
    {
        var client = httpClientFactory.CreateClient(ClientName);

        var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"]    = "client_credentials",
            ["client_id"]     = _s.ClientId,
            ["client_secret"] = _s.ClientSecret,
            ["scope"]         = GraphScope
        });

        var response = await client.PostAsync(TokenUrl, content, ct);
        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("access_token").GetString()!;
    }

    // Lists all users in the Entra tenant via Graph GET /v1.0/users.
    // Returns the same UserSummary shape that Keycloak returned so endpoints stay unchanged.
    public async Task<List<UserSummary>> GetUsersAsync(string adminToken, CancellationToken ct = default)
    {
        var client = httpClientFactory.CreateClient(ClientName);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);

        var response = await client.GetAsync($"{GraphBase}/users", ct);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException("Failed to retrieve users.");

        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);

        // Graph returns { "value": [ { "id": ..., "displayName": ..., ... }, ... ] }
        if (!doc.RootElement.TryGetProperty("value", out var valueEl))
            return [];

        return valueEl.EnumerateArray().Select(u => new UserSummary(
            u.TryGetProperty("id",          out var id) ? id.GetString()!  : string.Empty,
            u.TryGetProperty("userPrincipalName", out var upn) ? upn.GetString()! : string.Empty,
            u.TryGetProperty("mail",        out var em) ? em.GetString()!  : string.Empty,
            u.TryGetProperty("givenName",   out var fn) ? fn.GetString()!  : string.Empty,
            u.TryGetProperty("surname",     out var ln) ? ln.GetString()!  : string.Empty,
            u.TryGetProperty("accountEnabled", out var en) && en.GetBoolean()
        )).ToList();
    }

    // Assigns an app role to a user via Graph POST /v1.0/users/{id}/appRoleAssignments.
    // The role must be defined in the AntKart-API app registration; only "admin" and "user" are valid.
    // Unlike Keycloak's two-step role assignment (fetch role object → POST), Graph needs:
    //   - principalId: the user's Object ID
    //   - resourceId:  the API app's service principal Object ID
    //   - appRoleId:   the GUID of the role defined in the app registration
    public async Task AssignRoleAsync(string userId, string role, string adminToken, CancellationToken ct = default)
    {
        // Resolve role name → role GUID from the app registration manifest.
        var roleId = await ResolveRoleIdAsync(role, adminToken, ct);
        if (roleId is null)
            throw new KeyNotFoundException($"Role '{role}' not found in the app registration.");

        var client = httpClientFactory.CreateClient(ClientName);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);

        var assignUrl = $"{GraphBase}/users/{userId}/appRoleAssignments";
        var body = JsonSerializer.Serialize(new
        {
            principalId = userId,
            resourceId  = _s.ApiObjectId,
            appRoleId   = roleId
        });

        var response = await client.PostAsync(assignUrl,
            new StringContent(body, Encoding.UTF8, "application/json"), ct);

        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"Failed to assign role '{role}' to user '{userId}'.");
    }

    // Fetches the app registration's appRoles to resolve a role name → its GUID.
    // This mirrors Keycloak's two-call pattern: fetch role object, then assign.
    private async Task<string?> ResolveRoleIdAsync(string roleName, string adminToken, CancellationToken ct)
    {
        var client = httpClientFactory.CreateClient(ClientName);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", adminToken);

        // GET the service principal's app roles by its Object ID.
        var url = $"{GraphBase}/servicePrincipals/{_s.ApiObjectId}/appRoles";
        var response = await client.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode) return null;

        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);

        if (!doc.RootElement.TryGetProperty("value", out var roles)) return null;

        foreach (var r in roles.EnumerateArray())
        {
            if (r.TryGetProperty("value", out var val) &&
                string.Equals(val.GetString(), roleName, StringComparison.OrdinalIgnoreCase) &&
                r.TryGetProperty("id", out var id))
                return id.GetString();
        }

        return null;
    }
}
