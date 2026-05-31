using AK.UserIdentity.API.DTOs;

namespace AK.UserIdentity.API.Services;

public interface IIdentityService
{
    Task<TokenResponse> LoginAsync(string username, string password, CancellationToken ct = default);
    Task RegisterAsync(RegisterRequest request, CancellationToken ct = default);
    Task<TokenResponse> RefreshTokenAsync(string refreshToken, CancellationToken ct = default);
    Task<UserInfoResponse> GetUserInfoAsync(string accessToken, CancellationToken ct = default);
}

public interface IIdentityAdminService
{
    Task<List<UserSummary>> GetUsersAsync(string adminToken, CancellationToken ct = default);
    Task AssignRoleAsync(string userId, string role, string adminToken, CancellationToken ct = default);
    Task<string> GetAdminTokenAsync(CancellationToken ct = default);
}
