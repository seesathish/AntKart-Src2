# =============================================================================
# AK.Products.API — Dockerfile
#
# Two-stage build:
#   1. build  — full .NET SDK (MSBuild, NuGet, compilers). Standard image.
#   2. final  — antkart-base (chiseled, non-root, no shell). Pulled from ACR.
#
# WHY THE BUILD STAGE IS NOT CHISELED:
#   Chiseled images strip MSBuild, NuGet CLI, and shell — the build needs all
#   three. We use the standard SDK image at build time and copy only the
#   published output into the chiseled runtime image.
#
# WHY THE FINAL STAGE PULLS FROM ACR (NOT mcr.microsoft.com):
#   See docker/base/Dockerfile for full rationale. Short version:
#     - One hardened base for all 8 services (consistency, single fix point)
#     - Supply-chain control (we choose when to update from upstream)
#     - Faster AKS pulls (Azure backbone, no internet egress)
#     - Target for Week 11 admission policy (Trivy + signed-digest gating)
#
# BUILD ORDER (chicken-and-egg note):
#   This Dockerfile FROMs acrantkartdev.azurecr.io/antkart-base:9.0. That image
#   must exist in ACR before this builds. Run Week 7 commands in order:
#     (1) az acr build the base image,
#     (2) az acr build this service image.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["AK.Products/AK.Products.API/AK.Products.API.csproj", "AK.Products/AK.Products.API/"]
COPY ["AK.Products/AK.Products.Application/AK.Products.Application.csproj", "AK.Products/AK.Products.Application/"]
COPY ["AK.Products/AK.Products.Domain/AK.Products.Domain.csproj", "AK.Products/AK.Products.Domain/"]
COPY ["AK.Products/AK.Products.Infrastructure/AK.Products.Infrastructure.csproj", "AK.Products/AK.Products.Infrastructure/"]
COPY ["AK.BuildingBlocks/AK.BuildingBlocks/AK.BuildingBlocks.csproj", "AK.BuildingBlocks/AK.BuildingBlocks/"]
COPY ["nuget.config", "."]
RUN dotnet restore "AK.Products/AK.Products.API/AK.Products.API.csproj" --configfile nuget.config
COPY . .
WORKDIR "/src/AK.Products/AK.Products.API"
RUN dotnet publish "AK.Products.API.csproj" -c Release -o /app/publish /p:UseAppHost=false

# -----------------------------------------------------------------------------
# Final stage — hardened chiseled base from ACR.
# Inherits from antkart-base: non-root user (1654), invariant globalization,
# ASPNETCORE_URLS=http://+:8080, EXPOSE 8080. No further hardening needed here.
# -----------------------------------------------------------------------------
FROM acrantkartdev.azurecr.io/antkart-base:9.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "AK.Products.API.dll"]
