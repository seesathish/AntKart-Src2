using AK.BuildingBlocks.Messaging;
using AK.BuildingBlocks.Resilience;
using AK.Order.Application.Consumers;
using AK.Order.Application.Common.Interfaces;
using AK.Order.Application.Sagas;
using AK.Order.Infrastructure.Persistence;
using MassTransit;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AK.Order.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connStr = configuration.GetConnectionString("Postgres")
            ?? throw new InvalidOperationException("Connection string 'Postgres' is missing.");

        services.AddDbContext<OrderDbContext>(opts =>
            opts.UseNpgsql(connStr));

        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddNpgsqlResilience();

        services.AddServiceBusMassTransit(configuration, "order", cfg =>
        {
            cfg.AddSagaStateMachine<OrderSaga, OrderSagaState>()
               .EntityFrameworkRepository(r =>
               {
                   r.ConcurrencyMode = ConcurrencyMode.Optimistic;
                   r.ExistingDbContext<OrderDbContext>();
                   r.UsePostgres();
               });

            cfg.AddEntityFrameworkOutbox<OrderDbContext>(o =>
            {
                o.UsePostgres();
                o.UseBusOutbox();
            });

            cfg.AddConsumer<OrderConfirmedConsumer>();
            cfg.AddConsumer<OrderCancelledConsumer>();
            cfg.AddConsumer<PaymentSucceededConsumer>();
            cfg.AddConsumer<PaymentFailedConsumer>();
        });

        return services;
    }
}
