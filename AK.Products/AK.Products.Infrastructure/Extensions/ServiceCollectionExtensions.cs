using AK.BuildingBlocks.Messaging;
using AK.BuildingBlocks.Resilience;
using AK.Products.Application.Consumers;
using AK.Products.Application.Interfaces;
using AK.Products.Infrastructure.Grpc;
using AK.Products.Infrastructure.Persistence;
using AK.Products.Infrastructure.Persistence.Repositories;
using AK.Products.Infrastructure.Seeders;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AK.Products.Infrastructure.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        ProductClassMap.Register();
        services.Configure<MongoDbSettings>(configuration.GetSection("MongoDbSettings"));
        services.AddSingleton<MongoDbContext>();
        services.AddScoped<IProductRepository, ProductRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();
        services.AddScoped<ProductSeeder>();

        services.Configure<DiscountGrpcSettings>(configuration.GetSection("DiscountGrpc"));
        services.AddHttpClient("discount-grpc", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(10);
        })
        .AddHttpResilienceWithCircuitBreaker(maxRetryAttempts: 3, failureRatio: 0.5, minimumThroughput: 3, breakDurationSeconds: 30);
        services.AddScoped<IDiscountGrpcClient, DiscountGrpcClient>();

        services.AddServiceBusMassTransit(configuration, "products", cfg =>
        {
            cfg.AddConsumer<ReserveStockConsumer>();
        });

        return services;
    }
}
