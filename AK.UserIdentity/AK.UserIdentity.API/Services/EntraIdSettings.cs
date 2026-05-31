namespace AK.UserIdentity.API.Services;

// Settings specific to the UserIdentity service's admin operations against Microsoft Entra ID.
// These extend the shared AzureAdSettings (TenantId, ClientId, Audience) with fields needed
// for Graph API calls (user creation, role assignment) that no other service requires.
//
// ClientSecret is a secret — in production, inject via environment variable or Key Vault.
// Locally: dotnet user-secrets set "EntraId:ClientSecret" "<value>"
public sealed class EntraIdSettings
{
    public string TenantId { get; init; } = string.Empty;
    public string ClientId { get; init; } = string.Empty;
    public string ClientSecret { get; init; } = string.Empty;

    // Default domain of the Entra tenant — used to construct userPrincipalName on registration.
    // Format: <tenantname>.onmicrosoft.com — find it in Azure Portal → Entra ID → Overview.
    public string TenantDomain { get; init; } = string.Empty;

    // Service principal Object ID of the API app registration (AntKart-API).
    // Required for appRoleAssignments: the POST body must reference the resource's service principal.
    // Obtain from: Terraform output products_principal_id, or
    //   az ad sp show --id <clientId> --query id -o tsv
    public string ApiObjectId { get; init; } = string.Empty;

    // GUID of the "user" app role defined in the AntKart-API app registration.
    // Obtain from Terraform output or:
    //   az ad app show --id <clientId> --query "appRoles[?value=='user'].id" -o tsv
    public string UserRoleId { get; init; } = string.Empty;
}
