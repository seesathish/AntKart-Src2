# =============================================================================
# AK.Discount.Grpc — Dockerfile
# Inherits from acrantkartdev.azurecr.io/antkart-base:9.0 — see docker/base/Dockerfile.
#
# SQLite NOTE:
#   The original Dockerfile created /app/data via `RUN mkdir -p /app/data && chown ...`
#   to give the SQLite file a writable path. Chiseled images have no mkdir or
#   chown binary — and they don't need them. Both runtime paths to a writable
#   /app/data already work:
#     - docker-compose: the named volume `discount_data:/app/data` is created and
#       owned by the host's Docker daemon when the container starts.
#     - AKS (Week 8+): a PersistentVolumeClaim mounted at /app/data does the same.
#   So the mkdir/chown was redundant and is removed here.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.Discount/AK.Discount.Grpc/AK.Discount.Grpc.csproj", "AK.Discount/AK.Discount.Grpc/"]
COPY ["AK.Discount/AK.Discount.Application/AK.Discount.Application.csproj", "AK.Discount/AK.Discount.Application/"]
COPY ["AK.Discount/AK.Discount.Domain/AK.Discount.Domain.csproj", "AK.Discount/AK.Discount.Domain/"]
COPY ["AK.Discount/AK.Discount.Infrastructure/AK.Discount.Infrastructure.csproj", "AK.Discount/AK.Discount.Infrastructure/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.Discount/AK.Discount.Grpc/AK.Discount.Grpc.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.Discount/AK.Discount.Grpc"
RUN dotnet publish "AK.Discount.Grpc.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "AK.Discount.Grpc.dll"]
