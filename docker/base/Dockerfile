# =============================================================================
# ANTKART HARDENED BASE IMAGE — docker/base/Dockerfile
#
# PURPOSE:
#   Single hardened ASP.NET runtime base image that every AntKart microservice
#   inherits from. Published to ACR as:
#       acrantkartdev.azurecr.io/antkart-base:9.0
#       acrantkartdev.azurecr.io/antkart-base:<sha-or-date>
#
# WHY A CUSTOM BASE INSTEAD OF FROM mcr.microsoft.com DIRECTLY?
#
#   1. Supply-chain control. If Microsoft yanks or rebuilds a tag, our services
#      keep building from our pinned copy in ACR. We choose when to pull a new
#      upstream version, not the registry. This is the same reason production
#      images never use ":latest".
#
#   2. Pull performance. AKS kubelet pulls from ACR over the Azure backbone
#      (no internet). Faster cold-starts, no egress charges, lower MTTR.
#
#   3. One place to add hardening. Globalization defaults, telemetry opt-out,
#      labels, future CA bundles, future scan-attestation labels all live here.
#      Eight services inherit them automatically — fix once, not eight times.
#
#   4. Future admission-policy target. In Week 11 we add Trivy scanning and an
#      AKS admission webhook that rejects images whose base layer hash is not
#      our signed antkart-base hash. That policy is impossible if every service
#      pulls a different upstream tag.
#
# WHY CHISELED (mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled)?
#
#   Chiseled images contain only the .NET runtime, OpenSSL, ca-certificates,
#   and a non-root user. They do NOT contain:
#       - a shell (no /bin/sh, no /bin/bash)
#       - apt, dpkg, debconf
#       - coreutils (no ls, cat, grep, ps)
#       - ICU globalization data
#
#   Benefits:
#       - Tiny attack surface. CVEs against bash/coreutils/apt cannot apply
#         because those binaries are absent. Image size ~115 MB vs ~220 MB
#         for the standard runtime image.
#       - Non-root by default. The image's APP_UID environment variable is
#         set to 1654 (a defined user with no shell).
#       - Distroless-style: nothing to compromise into a shell from.
#
#   Cost — debugging implication:
#       `kubectl exec -it <pod> -- /bin/sh` will NOT work. There is no shell
#       in the running container. To poke around at runtime, attach an
#       ephemeral debug container with a full toolchain:
#
#           kubectl debug -it <pod> \
#               --image=mcr.microsoft.com/dotnet/runtime-deps:9.0 \
#               --target=<container-name>
#
#       The ephemeral container shares the pod's process namespace so you can
#       `ls /proc/1/root` to see the app's filesystem and read its logs and
#       open file descriptors. This is the modern Kubernetes-native answer
#       to "I need a shell" and is documented in DevelopmentGuide §7.7.
#
# WHY THIS BASE IMAGE IS NOT SCANNED OR SIGNED YET:
#   Trivy scanning + cosign attestation + AKS admission policy come in Week 11.
#   For Week 7 the goal is the supply-chain pattern (one ACR-hosted base for
#   all services). Security hardening on top is layered on later.
# =============================================================================

# -----------------------------------------------------------------------------
# FROM — pin the upstream chiseled ASP.NET runtime
#
#   noble-chiseled = Ubuntu 24.04 ("Noble Numbat") chiseled.
#   9.0            = .NET 9 GA runtime, matching <TargetFramework>net9.0</TargetFramework>.
#
# We intentionally pin to the major-minor tag (9.0), not a digest sha. The
# trade-off:
#     Pinning to 9.0       — picks up Microsoft's patches automatically when we rebuild
#     Pinning to @sha256:… — fully immutable but requires manual updates for every CVE patch
#
# For a learning/portfolio repo, 9.0 is fine. A regulated production environment
# would pin the SHA and re-pin on every patch release via Dependabot/Renovate.
# -----------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled

# -----------------------------------------------------------------------------
# OCI image labels — discoverability and provenance
#
# Standard image annotation schema (opencontainers.org/image-spec). These show
# up in ACR's portal "Repository" view and via `docker inspect`. Useful for
# audit ("which version of the base did this prod image inherit from?") and
# for the Week 11 admission policy.
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="antkart-base" \
      org.opencontainers.image.description="Hardened .NET 9 ASP.NET base image for AntKart microservices" \
      org.opencontainers.image.vendor="AntKart" \
      org.opencontainers.image.source="https://github.com/seesathish/AntKart-Src2" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.base.name="mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled"

# -----------------------------------------------------------------------------
# Environment defaults — applied to every service that inherits from this image
#
# DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true
#   Chiseled images do NOT ship ICU (International Components for Unicode).
#   Without ICU, .NET cannot perform culture-sensitive operations (formatting
#   currency by locale, comparing strings under a specific culture, etc.) and
#   throws at runtime if you try.
#
#   AntKart formats currency with `:N2` and `₹` (rupee literal) in a few
#   places (Notification templates, the Function summary line). These use the
#   invariant culture's group separator (comma) which IS available in invariant
#   mode — so this flag is safe. If any service later needs locale-aware
#   formatting, override this flag in that service's Dockerfile and either:
#       (a) install the icu-libs chiseled extra, or
#       (b) move that service back to the non-chiseled runtime.
#
# ASPNETCORE_URLS=http://+:8080
#   Tells Kestrel to listen on port 8080 on all interfaces. Standardising on
#   8080 across every service means Helm values and ConfigMaps don't need
#   per-service port logic. AK.Gateway overrides this in its own Dockerfile
#   because it must listen on 8000.
#
# DOTNET_PRINT_TELEMETRY_MESSAGE=false + DOTNET_NOLOGO=true
#   Suppress the "Welcome to .NET" banner and telemetry notice from container
#   logs. They add noise to startup logs and disturb log-shipping pipelines
#   that key on the first line being structured JSON.
#
# DOTNET_RUNNING_IN_CONTAINER=true
#   Hints to the runtime that we're in a container so it tunes GC, file-watcher,
#   and TLS defaults appropriately. Microsoft's official images already set this
#   but we re-state it as documentation.
# -----------------------------------------------------------------------------
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true \
    DOTNET_PRINT_TELEMETRY_MESSAGE=false \
    DOTNET_NOLOGO=true \
    DOTNET_RUNNING_IN_CONTAINER=true \
    ASPNETCORE_URLS=http://+:8080

# -----------------------------------------------------------------------------
# Non-root user
#
# The upstream chiseled image already defines APP_UID=1654 and ships a user
# entry for it in /etc/passwd. We make non-root the explicit default here so
# any FROM-of-this-image service inherits it without remembering to set it.
#
# Why 1654 (not 1000)?
#   It's the Microsoft-blessed UID for chiseled .NET containers. Hardcoding it
#   lets Kubernetes PodSecurity policies set `runAsUser: 1654` consistently
#   across the fleet. We use this in the Helm chart's pod security context.
# -----------------------------------------------------------------------------
USER $APP_UID

# -----------------------------------------------------------------------------
# Default port
#
# Document the contract: this base exposes 8080. Service Dockerfiles override
# only if they need a different port (Gateway = 8000).
#
# Note: EXPOSE is purely declarative metadata. It does NOT open a port. The
# port becomes reachable only when Kubernetes (or `docker run -p`) maps it.
# -----------------------------------------------------------------------------
EXPOSE 8080

# No CMD or ENTRYPOINT. Each service sets its own in its own Dockerfile —
# typically `ENTRYPOINT ["dotnet", "AK.<Service>.dll"]`.
