using AK.BuildingBlocks.Authentication;
using AK.BuildingBlocks.HealthChecks;
using AK.BuildingBlocks.Logging;
using AK.BuildingBlocks.Swagger;
using AK.BuildingBlocks.Messaging;
using AK.UserIdentity.API.Endpoints;
using AK.UserIdentity.API.Middleware;
using AK.UserIdentity.API.Services;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(o => o.AddServerHeader = false);

builder.AddSerilogLogging();

builder.Services.AddEntraIdAuthentication(builder.Configuration);
builder.Services.AddDefaultHealthChecks();
builder.Services.AddServiceBusMassTransit(builder.Configuration, "identity", _ => { });

builder.Services.AddHttpClient("entra-id", client =>
{
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.Configure<EntraIdSettings>(builder.Configuration.GetSection("EntraId"));
builder.Services.AddScoped<IIdentityService, EntraIdService>();
builder.Services.AddScoped<IIdentityAdminService, EntraIdAdminService>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new() { Title = "AK.UserIdentity API", Version = "v1", Description = "AntKart User Identity Microservice — Microsoft Entra ID auth proxy" });
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

app.UseMiddleware<ExceptionHandlerMiddleware>();

app.UseSwaggerInDevelopment("AK.UserIdentity API v1");

app.UseEntraIdAuth();

app.MapAuthEndpoints();
app.MapAdminEndpoints();
app.MapDefaultHealthChecks();

app.Run();

public partial class Program { }
