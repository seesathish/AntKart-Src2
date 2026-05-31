using AK.UserIdentity.API.DTOs;
using AK.UserIdentity.API.Services;
using Microsoft.AspNetCore.Mvc;

namespace AK.UserIdentity.API.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/auth").WithTags("Auth");

        // POST /api/auth/login
        group.MapPost("/login", async ([FromBody] LoginRequest req, IIdentityService svc, CancellationToken ct) =>
        {
            var token = await svc.LoginAsync(req.Username, req.Password, ct);
            return Results.Ok(token);
        })
        .AllowAnonymous()
        .WithName("Login")
        .WithSummary("Login with username and password, returns JWT tokens");

        // POST /api/auth/register
        group.MapPost("/register", async ([FromBody] RegisterRequest req, IIdentityService svc, CancellationToken ct) =>
        {
            await svc.RegisterAsync(req, ct);
            return Results.Created("/api/auth/login", new { message = "User registered successfully." });
        })
        .AllowAnonymous()
        .WithName("Register")
        .WithSummary("Register a new user (assigned 'user' role by default)");

        // POST /api/auth/refresh
        group.MapPost("/refresh", async ([FromBody] RefreshRequest req, IIdentityService svc, CancellationToken ct) =>
        {
            var token = await svc.RefreshTokenAsync(req.RefreshToken, ct);
            return Results.Ok(token);
        })
        .AllowAnonymous()
        .WithName("RefreshToken")
        .WithSummary("Refresh an access token using a refresh token");

        // GET /api/auth/me
        group.MapGet("/me", async (HttpContext httpContext, IIdentityService svc, CancellationToken ct) =>
        {
            var authHeader = httpContext.Request.Headers.Authorization.ToString();
            if (string.IsNullOrEmpty(authHeader) || !authHeader.StartsWith("Bearer "))
                return Results.Unauthorized();

            var token = authHeader["Bearer ".Length..];
            var userInfo = await svc.GetUserInfoAsync(token, ct);
            return Results.Ok(userInfo);
        })
        .RequireAuthorization("authenticated")
        .WithName("GetMe")
        .WithSummary("Get current authenticated user info");
    }
}
