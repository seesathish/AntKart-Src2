using AK.BuildingBlocks.Messaging.IntegrationEvents;
using AK.UserIdentity.API.DTOs;
using AK.UserIdentity.API.Services;
using FluentAssertions;
using MassTransit;
using Microsoft.Extensions.Options;
using Moq;
using Moq.Protected;
using System.Net;
using System.Text;
using System.Text.Json;

namespace AK.UserIdentity.Tests.Services;

public sealed class EntraIdServiceTests
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
    private readonly Mock<IPublishEndpoint> _publisher = new();

    private static IHttpClientFactory CreateFactory(HttpResponseMessage response)
    {
        var handler = new Mock<HttpMessageHandler>();
        handler.Protected()
            .Setup<Task<HttpResponseMessage>>("SendAsync",
                ItExpr.IsAny<HttpRequestMessage>(), ItExpr.IsAny<CancellationToken>())
            .ReturnsAsync(response);
        var client = new HttpClient(handler.Object);
        var factory = new Mock<IHttpClientFactory>();
        factory.Setup(f => f.CreateClient(It.IsAny<string>())).Returns(client);
        return factory.Object;
    }

    private static IHttpClientFactory CreateSequentialFactory(params HttpResponseMessage[] responses)
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
    public async Task LoginAsync_WithValidCredentials_ReturnsTokenResponse()
    {
        var tokenJson = JsonSerializer.Serialize(new
        {
            access_token  = "access.token.value",
            refresh_token = "refresh.token.value",
            expires_in    = 300,
            token_type    = "Bearer"
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(tokenJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var result = await svc.LoginAsync("user1", "pass1");

        result.AccessToken.Should().Be("access.token.value");
        result.RefreshToken.Should().Be("refresh.token.value");
        result.ExpiresIn.Should().Be(300);
        result.TokenType.Should().Be("Bearer");
    }

    [Fact]
    public async Task LoginAsync_WithInvalidCredentials_ThrowsUnauthorizedAccessException()
    {
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.Unauthorized)
        {
            Content = new StringContent("{\"error\":\"invalid_grant\"}", Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var act = async () => await svc.LoginAsync("bad", "creds");

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task RefreshTokenAsync_WithValidToken_ReturnsNewTokens()
    {
        var tokenJson = JsonSerializer.Serialize(new
        {
            access_token  = "new.access.token",
            refresh_token = "new.refresh.token",
            expires_in    = 300,
            token_type    = "Bearer"
        });
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(tokenJson, Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var result = await svc.RefreshTokenAsync("old.refresh.token");

        result.AccessToken.Should().Be("new.access.token");
    }

    [Fact]
    public async Task RefreshTokenAsync_WithInvalidToken_ThrowsUnauthorizedAccessException()
    {
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent("{\"error\":\"invalid_grant\"}", Encoding.UTF8, "application/json")
        });

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var act = async () => await svc.RefreshTokenAsync("bad.token");

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task GetUserInfoAsync_WithValidJwt_ReturnsUserInfoFromClaims()
    {
        // Build a minimal JWT with the claims we expect GetUserInfoAsync to parse.
        // Header and signature don't need to be valid — the method only decodes the payload.
        var payload = Convert.ToBase64String(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new
        {
            oid                = "user-oid-123",
            preferred_username = "john.doe@testdomain.onmicrosoft.com",
            email              = "john@example.com",
            given_name         = "John",
            family_name        = "Doe",
            roles              = new[] { "user" }
        }))).TrimEnd('=');

        var fakeJwt = $"header.{payload}.signature";
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK));

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var result = await svc.GetUserInfoAsync(fakeJwt);

        result.Id.Should().Be("user-oid-123");
        result.Email.Should().Be("john@example.com");
        result.Roles.Should().Contain("user");
    }

    [Fact]
    public async Task GetUserInfoAsync_WithMalformedToken_ThrowsUnauthorizedAccessException()
    {
        var factory = CreateFactory(new HttpResponseMessage(HttpStatusCode.OK));
        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var act = async () => await svc.GetUserInfoAsync("not.a.valid.jwt.format.with.too.many.dots");

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task RegisterAsync_WithValidRequest_PublishesUserRegisteredEvent()
    {
        // Sequence: (1) app token, (2) create user → 201 + id, (3) assign role
        var appTokenJson = JsonSerializer.Serialize(new { access_token = "app.token", expires_in = 300, token_type = "Bearer" });
        var createdUserJson = JsonSerializer.Serialize(new { id = "new-user-oid" });

        var factory = CreateSequentialFactory(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(appTokenJson, Encoding.UTF8, "application/json")
            },
            new HttpResponseMessage(HttpStatusCode.Created)
            {
                Content = new StringContent(createdUserJson, Encoding.UTF8, "application/json")
            },
            new HttpResponseMessage(HttpStatusCode.Created)); // appRoleAssignment

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        await svc.RegisterAsync(new RegisterRequest("john", "john@example.com", "Pass1!", "John", "Doe"));

        _publisher.Verify(p => p.Publish(
            It.Is<UserRegisteredIntegrationEvent>(e =>
                e.UserId == "new-user-oid" &&
                e.CustomerEmail == "john@example.com" &&
                e.CustomerName == "John Doe"),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task RegisterAsync_WhenGraphReturns400WithUserPrincipalName_ThrowsInvalidOperationException()
    {
        var appTokenJson = JsonSerializer.Serialize(new { access_token = "app.token", expires_in = 300, token_type = "Bearer" });

        var factory = CreateSequentialFactory(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(appTokenJson, Encoding.UTF8, "application/json")
            },
            new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent("{\"error\":{\"message\":\"Property userPrincipalName is invalid\"}}", Encoding.UTF8, "application/json")
            });

        var svc = new EntraIdService(factory, Options.Create(_settings), _publisher.Object);
        var act = async () => await svc.RegisterAsync(new RegisterRequest("john", "john@example.com", "Pass1!", "John", "Doe"));

        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("*already exists*");
    }
}
