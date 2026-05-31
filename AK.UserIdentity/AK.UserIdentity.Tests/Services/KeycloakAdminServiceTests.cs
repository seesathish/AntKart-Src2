using AK.UserIdentity.API.DTOs;
using AK.UserIdentity.API.Services;
using FluentAssertions;
using Microsoft.Extensions.Options;
using Moq;
using Moq.Protected;
using System.Net;
using System.Text;
using System.Text.Json;

namespace AK.UserIdentity.Tests.Services;

public sealed class EntraIdAdminServiceTests
{
    private readonly EntraIdSettings _settings = new()
    {
        TenantId     = "test-tenant-id",
        ClientId     = "test-client-id",
        ClientSecret = "test-secret",
        TenantDomain = "testdomain.onmicrosoft.com",
        ApiObjectId  = "api-object-id",
        UserRoleId   = "user-role-guid"
    };

    private static IHttpClientFactory CreateFactory(params HttpResponseMessage[] responses)
    {
        var queue = new Queue<HttpResponseMessage>(responses);
        var handler = new Mock<HttpMessageHandler>();
        handler.Protected()
            .Setup<Task<HttpResponseMessage>>("SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(), ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(() => queue.Count > 0 ? queue.Dequeue() : new HttpResponseMessage(HttpStatusCode.OK));
        var client = new HttpClient(handler.Object);
        var factory = new Mock<IHttpClientFactory>();
        factory.Setup(f => f.CreateClient(It.IsAny<string>())).Returns(client);
        return factory.Object;
    }

    [Fact]
    public async Task GetAdminTokenAsync_WithValidClientCredentials_ReturnsAccessToken()
    {
        var tokenJson = JsonSerializer.Serialize(new
        {
            access_token = "service.account.token",
            expires_in   = 60,
            token_type   = "Bearer"
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(tokenJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var token = await svc.GetAdminTokenAsync();

        token.Should().Be("service.account.token");
    }

    [Fact]
    public async Task GetUsersAsync_ReturnsListOfUsers()
    {
        // Graph API returns { "value": [ ... ] }
        var usersJson = JsonSerializer.Serialize(new
        {
            value = new[]
            {
                new { id = "id1", userPrincipalName = "alice@testdomain.onmicrosoft.com", mail = "alice@example.com", givenName = "Alice", surname = "Smith", accountEnabled = true },
                new { id = "id2", userPrincipalName = "bob@testdomain.onmicrosoft.com",   mail = "bob@example.com",   givenName = "Bob",   surname = "Jones", accountEnabled = true }
            }
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(usersJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var result = await svc.GetUsersAsync("admin.token");

        result.Should().HaveCount(2);
        result[0].Username.Should().Be("alice@testdomain.onmicrosoft.com");
        result[1].Username.Should().Be("bob@testdomain.onmicrosoft.com");
    }

    [Fact]
    public async Task GetUsersAsync_WhenApiFails_ThrowsInvalidOperationException()
    {
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.Forbidden));

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var act = async () => await svc.GetUsersAsync("bad.token");

        await act.Should().ThrowAsync<InvalidOperationException>();
    }

    [Fact]
    public async Task GetUsersAsync_WithUsersHavingNoOptionalFields_ReturnsEmptyStringsForMissingFields()
    {
        var usersJson = JsonSerializer.Serialize(new
        {
            value = new[]
            {
                new { id = "id-minimal", accountEnabled = false }
            }
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(usersJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var result = await svc.GetUsersAsync("admin.token");

        result.Should().HaveCount(1);
        result[0].Id.Should().Be("id-minimal");
        result[0].Email.Should().BeEmpty();
        result[0].Enabled.Should().BeFalse();
    }

    [Fact]
    public async Task AssignRoleAsync_WithValidRole_Succeeds()
    {
        // Sequence: (1) GET appRoles from service principal, (2) POST appRoleAssignments
        var rolesJson = JsonSerializer.Serialize(new
        {
            value = new[] { new { id = "user-role-guid", value = "user", displayName = "User" } }
        });
        var factory = CreateFactory(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(rolesJson, Encoding.UTF8, "application/json")
            },
            new HttpResponseMessage(HttpStatusCode.Created));

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var act = async () => await svc.AssignRoleAsync("user-id", "user", "admin.token");

        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task AssignRoleAsync_WithNonExistentRole_ThrowsKeyNotFoundException()
    {
        // The appRoles list exists but doesn't contain the requested role name
        var rolesJson = JsonSerializer.Serialize(new
        {
            value = new[] { new { id = "user-role-guid", value = "user", displayName = "User" } }
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(rolesJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var act = async () => await svc.AssignRoleAsync("user-id", "nonexistent", "admin.token");

        await act.Should().ThrowAsync<KeyNotFoundException>().WithMessage("*nonexistent*");
    }

    [Fact]
    public async Task AssignRoleAsync_WhenAssignmentPostFails_ThrowsInvalidOperationException()
    {
        // Step 1 (GET roles) succeeds; Step 2 (POST assignment) returns 500
        var rolesJson = JsonSerializer.Serialize(new
        {
            value = new[] { new { id = "admin-role-guid", value = "admin", displayName = "Admin" } }
        });
        var factory = CreateFactory(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(rolesJson, Encoding.UTF8, "application/json")
            },
            new HttpResponseMessage(HttpStatusCode.InternalServerError));

        var svc = new EntraIdAdminService(factory, Options.Create(_settings));
        var act = async () => await svc.AssignRoleAsync("user-id", "admin", "admin.token");

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*Failed to assign role*");
    }
}
