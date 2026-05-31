using AK.UserIdentity.API.DTOs;
using AK.UserIdentity.API.Services;
using Microsoft.AspNetCore.Mvc;

namespace AK.UserIdentity.API.Endpoints;

// Admin-only endpoints that proxy through to Microsoft Entra ID via Graph API.
// Every request obtains a fresh short-lived service-account token (client_credentials)
// before calling Graph — we don't cache it here because the token lifetime is short
// and caching adds complexity. The "admin" authorization policy requires the caller's
// JWT to contain the "admin" app role defined in the AntKart-API app registration.
public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/admin").WithTags("Admin")
            .RequireAuthorization("admin");

        // GET /api/admin/users — returns all users in the Entra tenant.
        group.MapGet("/users", async (IIdentityAdminService adminSvc, CancellationToken ct) =>
        {
            var adminToken = await adminSvc.GetAdminTokenAsync(ct);
            var users = await adminSvc.GetUsersAsync(adminToken, ct);
            return Results.Ok(users);
        })
        .WithName("GetAllUsers")
        .WithSummary("Get all registered users (Admin only)");

        // POST /api/admin/users/{id}/roles — assigns an Entra app role to a user.
        // Flow: resolve role name → GUID via Graph servicePrincipals/{id}/appRoles
        //       → POST /users/{id}/appRoleAssignments with principalId + resourceId + appRoleId.
        group.MapPost("/users/{id}/roles", async (
            string id,
            [FromBody] AssignRoleRequest req,
            IIdentityAdminService adminSvc,
            CancellationToken ct) =>
        {
            var adminToken = await adminSvc.GetAdminTokenAsync(ct);
            await adminSvc.AssignRoleAsync(id, req.Role, adminToken, ct);
            return Results.Ok(new { message = $"Role '{req.Role}' assigned to user '{id}'." });
        })
        .WithName("AssignRole")
        .WithSummary("Assign an app role to a user (Admin only)");
    }
}
