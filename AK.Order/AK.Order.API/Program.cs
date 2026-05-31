using AK.BuildingBlocks.Authentication;
using AK.BuildingBlocks.HealthChecks;
using AK.BuildingBlocks.Logging;
using AK.BuildingBlocks.Swagger;
using AK.BuildingBlocks.Versioning;
using AK.Order.API.Endpoints;
using AK.BuildingBlocks.Middleware;
using AK.Order.Application.Extensions;
using AK.Order.Infrastructure.Extensions;

// Program.cs is the application entry point.
// The order of registration and middleware matters — comments explain why each step is here.

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(o => o.AddServerHeader = false);

// Replaces the default Microsoft.Extensions.Logging with Serilog.
// Serilog outputs structured JSON logs to console, rolling file, and Elasticsearch.
// Must be called before any other service registration so early startup logs are captured.
builder.AddSerilogLogging();

// AddApplication: MediatR, FluentValidation pipeline, validators, mappers
builder.Services.AddApplication();

// AddInfrastructure: EF Core (PostgreSQL), repositories, MassTransit (RabbitMQ + SAGA + Outbox)
builder.Services.AddInfrastructure(builder.Configuration);

// AddEntraIdAuthentication: JWT Bearer middleware backed by Entra ID, role extraction, admin/authenticated policies
builder.Services.AddEntraIdAuthentication(builder.Configuration);

// API versioning: default v1.0, URL segment (/api/v1/...) or header (api-version: 1.0).
// Other services adopt this by calling AddStandardApiVersioning() in their Program.cs.
builder.Services.AddStandardApiVersioning();

// Adds a /health endpoint that returns 200 when the service is running.
// Docker Compose uses this for depends_on health checks.
builder.Services.AddDefaultHealthChecks();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new() { Title = "AK.Order API", Version = "v1", Description = "AntKart Order Microservice — PostgreSQL-backed order management" });
    c.AddSecurityDefinition("Bearer", new Microsoft.OpenApi.Models.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.Models.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.Models.ParameterLocation.Header
    });
    c.AddSecurityRequirement(new Microsoft.OpenApi.Models.OpenApiSecurityRequirement
    {
        {
            new Microsoft.OpenApi.Models.OpenApiSecurityScheme
            {
                Reference = new Microsoft.OpenApi.Models.OpenApiReference
                {
                    Type = Microsoft.OpenApi.Models.ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// Runs any pending EF Core migrations automatically on startup.
// Ensures the DB schema is always up to date without manual migration steps.
await app.ApplyMigrationsAsync();

// Middleware order matters — ExceptionHandlerMiddleware must be registered FIRST
// so it wraps the entire request pipeline and catches exceptions from all subsequent middleware.
app.UseMiddleware<ExceptionHandlerMiddleware>();

app.UseSwaggerInDevelopment("AK.Order API v1");

// UseEntraIdAuth calls UseAuthentication() then UseAuthorization() in the correct order.
// Must come AFTER ExceptionHandlerMiddleware (so auth errors are caught) and BEFORE endpoint mapping.
app.UseEntraIdAuth();

app.MapOrderEndpoints();
app.MapDefaultHealthChecks();

app.Run();

// Partial class declaration makes the test project able to reference Program as a type
// for WebApplicationFactory integration tests (even though we don't use those here).
public partial class Program { }
