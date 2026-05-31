namespace AK.UserIdentity.API.DTOs;

public sealed record LoginRequest(string Username, string Password);

public sealed record RegisterRequest(
    string Username,
    string Email,
    string Password,
    string FirstName,
    string LastName);

public sealed record TokenResponse(
    string AccessToken,
    string RefreshToken,
    int ExpiresIn,
    string TokenType);

public sealed record RefreshRequest(string RefreshToken);

public sealed record UserInfoResponse(
    string Id,
    string Username,
    string Email,
    string FirstName,
    string LastName,
    List<string> Roles);

public sealed record AssignRoleRequest(string Role);

public sealed record UserSummary(
    string Id,
    string Username,
    string Email,
    string FirstName,
    string LastName,
    bool Enabled);
