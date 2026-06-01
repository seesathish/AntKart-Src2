# =============================================================================
# AK.Order.API — Dockerfile
# Inherits from acrantkartdev.azurecr.io/antkart-base:9.0 — see docker/base/Dockerfile
# for the chiseled / non-root / globalization-invariant rationale.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.Order/AK.Order.API/AK.Order.API.csproj", "AK.Order/AK.Order.API/"]
COPY ["AK.Order/AK.Order.Application/AK.Order.Application.csproj", "AK.Order/AK.Order.Application/"]
COPY ["AK.Order/AK.Order.Domain/AK.Order.Domain.csproj", "AK.Order/AK.Order.Domain/"]
COPY ["AK.Order/AK.Order.Infrastructure/AK.Order.Infrastructure.csproj", "AK.Order/AK.Order.Infrastructure/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.Order/AK.Order.API/AK.Order.API.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.Order/AK.Order.API"
RUN dotnet publish "AK.Order.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "AK.Order.API.dll"]
