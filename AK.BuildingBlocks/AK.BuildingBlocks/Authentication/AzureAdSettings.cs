namespace AK.BuildingBlocks.Authentication;

public sealed class AzureAdSettings
{
    public string TenantId { get; init; } = string.Empty;
    public string ClientId { get; init; } = string.Empty;
    public string Audience { get; init; } = string.Empty;
}
