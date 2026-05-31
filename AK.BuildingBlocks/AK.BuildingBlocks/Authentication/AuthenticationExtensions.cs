using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;

namespace AK.BuildingBlocks.Authentication;

// Shared JWT authentication setup used by every service (Products, Cart, Order, Payments, Notification).
// Calling AddEntraIdAuthentication() from a service's Program.cs wires up all of this automatically.
public static class AuthenticationExtensions
{
    // Registers JWT Bearer authentication backed by Microsoft Entra ID (Azure AD) as the identity provider.
    // Each service calls this once in Program.cs — no copy-pasting of JWT config per service.
    //
    // Auth flow:
    //   1. JWT Bearer middleware downloads signing keys from Entra's OIDC discovery endpoint
    //      at {Authority}/.well-known/openid-configuration automatically.
    //   2. Every inbound Bearer token is validated: signature, issuer, audience, and lifetime.
    //   3. App roles are mapped from the 'roles' claim (Entra standard) to ClaimTypes.Role
    //      so RequireAuthorization("admin") and RequireRole("admin") work natively.
    //   4. The IDOR-safe user ID comes from the 'oid' claim (Entra Object ID) via GetUserId()
    //      in HttpContextExtensions — stable across all apps in the tenant, never reused.
    public static IServiceCollection AddEntraIdAuthentication(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var settings = configuration.GetSection("AzureAd").Get<AzureAdSettings>()
            ?? throw new InvalidOperationException("AzureAd settings are missing from configuration.");

        services.Configure<AzureAdSettings>(configuration.GetSection("AzureAd"));

        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                // Entra ID v2.0 authority — the middleware downloads signing keys and issuer metadata
                // from https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration.
                options.Authority = $"https://login.microsoftonline.com/{settings.TenantId}/v2.0";

                // Audience validation: tokens must be issued for this API's Application ID URI.
                // Rejects tokens that were issued for a different resource (e.g., Microsoft Graph).
                options.Audience = settings.Audience;

                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true
                };

                options.Events = new JwtBearerEvents
                {
                    OnTokenValidated = ctx =>
                    {
                        var identity = ctx.Principal?.Identity as System.Security.Claims.ClaimsIdentity;
                        if (identity is null) return Task.CompletedTask;

                        // Entra ID encodes app roles as individual 'roles' claims in the access token
                        // (one Claim per role value). Map each to ClaimTypes.Role so
                        // RequireAuthorization("admin") and policy.RequireRole("admin") work without
                        // any special configuration in endpoint definitions.
                        foreach (var roleClaim in ctx.Principal!.FindAll("roles"))
                        {
                            identity.AddClaim(new System.Security.Claims.Claim(
                                System.Security.Claims.ClaimTypes.Role, roleClaim.Value));
                        }

                        return Task.CompletedTask;
                    }
                };
            });

        services.AddAuthorization(options =>
        {
            // "admin" policy: caller must have the "admin" app role in their Entra token.
            options.AddPolicy("admin", policy =>
                policy.RequireRole("admin"));

            // "authenticated" policy: caller just needs a valid JWT, any role is fine.
            options.AddPolicy("authenticated", policy =>
                policy.RequireAuthenticatedUser());
        });

        return services;
    }

    // Registers both UseAuthentication() and UseAuthorization() in the correct order.
    // Authentication must come before Authorization — calling them in the wrong order causes
    // authorization policies to always fail because the user identity hasn't been set yet.
    public static WebApplication UseEntraIdAuth(this WebApplication app)
    {
        app.UseAuthentication();
        app.UseAuthorization();
        return app;
    }
}
