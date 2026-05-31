using Microsoft.AspNetCore.Http;
using System.Security.Claims;

namespace AK.BuildingBlocks.Authentication;

// Helper methods for reading user identity from the Entra ID JWT inside an endpoint or handler.
//
// Security rule: user-scoped operations (get my cart, create my order) must ALWAYS derive
// the userId from the JWT via GetUserId(), never from a URL parameter or request body.
// This prevents IDOR (Insecure Direct Object Reference) attacks where a logged-in user
// could access or modify another user's data simply by changing a userId in the URL.
// GetUserId() reads the 'oid' claim (Entra Object ID) — stable across all apps in the tenant.
public static class HttpContextExtensions
{
    // Returns the caller's stable user UUID from the Entra ID 'oid' (Object ID) claim.
    //
    // WHY 'oid' and not 'sub':
    //   In Entra ID, 'sub' is pairwise — it is unique per (user, application) pair, meaning
    //   the same user gets a different 'sub' value when calling a different app. This makes
    //   'sub' unsafe for cross-service user correlation.
    //   'oid' is the stable Object ID in the tenant directory — it never changes for a given
    //   user, even after password reset, email change, or login from a different device.
    //   Using 'oid' as the user key is the IDOR-safe pattern for Entra ID.
    //
    // The long-form URI claim name is a fallback for token profiles that normalise the claim
    // type using the WS-Federation URN namespace before ASP.NET Core maps it to the short name.
    // Throws UnauthorizedAccessException (→ HTTP 403) if no identity claim is present.
    public static string GetUserId(this HttpContext ctx) =>
        ctx.User.FindFirst("oid")?.Value
        ?? ctx.User.FindFirst("http://schemas.microsoft.com/identity/claims/objectidentifier")?.Value
        ?? throw new UnauthorizedAccessException("User identity could not be determined from token.");

    // Returns the caller's email from the JWT 'email' claim.
    // Returns empty string (not null) if missing — email is optional for some operations.
    public static string GetUserEmail(this HttpContext ctx) =>
        ctx.User.FindFirst("email")?.Value
        ?? ctx.User.FindFirst(ClaimTypes.Email)?.Value
        ?? string.Empty;

    // Returns a human-readable display name, trying Entra ID standard claims in order.
    // Used when denormalising customer name into Order and Payment records so they don't
    // need to call the UserIdentity service to look up a name later.
    public static string GetUserDisplayName(this HttpContext ctx) =>
        ctx.User.FindFirst("name")?.Value
        ?? $"{ctx.User.FindFirst("given_name")?.Value} {ctx.User.FindFirst("family_name")?.Value}".Trim()
        ?? ctx.User.FindFirst("preferred_username")?.Value
        ?? "Customer";
}
