using AK.Notification.Application.Extensions;
using AK.Notification.Infrastructure.Extensions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

// Isolated worker model: this is a standalone .NET 9 process.
// The Functions runtime communicates with it over gRPC — no shared AppDomain with the host.
//
// DI strategy: call AddApplication() (MediatR + validators) and AddInfrastructureCore()
// (PostgreSQL, channels, template renderer) without MassTransit — the Service Bus trigger
// annotation on each Function class replaces the MassTransit consumer registration.
var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureAppConfiguration(config =>
    {
        config.AddJsonFile("local.settings.json", optional: true, reloadOnChange: false);
        config.AddEnvironmentVariables();
    })
    .ConfigureServices((ctx, services) =>
    {
        services.AddApplication();
        services.AddInfrastructureCore(ctx.Configuration);
    })
    .Build();

await host.RunAsync();
