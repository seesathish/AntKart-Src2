using AK.BuildingBlocks.Messaging;
using AK.Payments.Application.Common.Interfaces;
using AK.Payments.Application.Consumers;
using AK.Payments.Infrastructure.External;
using AK.Payments.Infrastructure.Persistence;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AK.Payments.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connStr = configuration.GetConnectionString("PaymentsDb")
            ?? throw new InvalidOperationException("Connection string 'PaymentsDb' is missing.");

        services.AddDbContext<PaymentsDbContext>(opts => opts.UseNpgsql(connStr));

        services.Configure<RazorpaySettings>(configuration.GetSection("Razorpay"));
        services.AddHttpClient("razorpay");
        services.AddScoped<IRazorpayClient, RazorpayGatewayClient>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddServiceBusMassTransit(configuration, "payments", cfg =>
        {
            cfg.AddEntityFrameworkOutbox<PaymentsDbContext>(o =>
            {
                o.UsePostgres();
                o.UseBusOutbox();
            });

            cfg.AddConsumer<OrderConfirmedConsumer>();
        });

        return services;
    }
}
