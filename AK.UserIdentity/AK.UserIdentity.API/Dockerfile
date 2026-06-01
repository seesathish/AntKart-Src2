# =============================================================================
# AK.UserIdentity.API — Dockerfile
# Inherits from acrantkartdev.azurecr.io/antkart-base:9.0 — see docker/base/Dockerfile.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.UserIdentity/AK.UserIdentity.API/AK.UserIdentity.API.csproj", "AK.UserIdentity/AK.UserIdentity.API/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.UserIdentity/AK.UserIdentity.API/AK.UserIdentity.API.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.UserIdentity/AK.UserIdentity.API"
RUN dotnet publish "AK.UserIdentity.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "AK.UserIdentity.API.dll"]
