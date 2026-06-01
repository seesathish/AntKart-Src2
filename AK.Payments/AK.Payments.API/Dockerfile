# =============================================================================
# AK.Payments.API — Dockerfile
# Inherits from acrantkartdev.azurecr.io/antkart-base:9.0 — see docker/base/Dockerfile.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.Payments/AK.Payments.API/AK.Payments.API.csproj", "AK.Payments/AK.Payments.API/"]
COPY ["AK.Payments/AK.Payments.Application/AK.Payments.Application.csproj", "AK.Payments/AK.Payments.Application/"]
COPY ["AK.Payments/AK.Payments.Domain/AK.Payments.Domain.csproj", "AK.Payments/AK.Payments.Domain/"]
COPY ["AK.Payments/AK.Payments.Infrastructure/AK.Payments.Infrastructure.csproj", "AK.Payments/AK.Payments.Infrastructure/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.Payments/AK.Payments.API/AK.Payments.API.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.Payments/AK.Payments.API"
RUN dotnet publish "AK.Payments.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "AK.Payments.API.dll"]
