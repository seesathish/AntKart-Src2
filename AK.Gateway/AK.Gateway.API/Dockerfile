# =============================================================================
# AK.Gateway.API — Dockerfile
# Inherits from acrantkartdev.azurecr.io/antkart-base:9.0 — see docker/base/Dockerfile.
#
# PORT OVERRIDE (the only service that does this):
#   The Ocelot gateway is the single client-facing entry point and listens on
#   port 8000, not the base image's 8080 default. We override ASPNETCORE_URLS
#   here and re-declare EXPOSE. Helm values for ak-gateway must also set
#   containerPort: 8000 and service.port: 8000 — see charts/values/gateway.yaml.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.Gateway/AK.Gateway.API/AK.Gateway.API.csproj", "AK.Gateway/AK.Gateway.API/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.Gateway/AK.Gateway.API/AK.Gateway.API.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.Gateway/AK.Gateway.API"
RUN dotnet publish "AK.Gateway.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:8000
EXPOSE 8000
ENTRYPOINT ["dotnet", "AK.Gateway.API.dll"]
