# ADR-015: AKS Cluster, Workload Identity, and Custom Hardened Base Image

## Status
Accepted

---

## Context

Phase 2C (Week 7) moves AntKart services from Docker Compose into Kubernetes. Three decisions had to be made together because each one constrains the others:

1. **How to run the cluster** — AKS sizing, node pools, networking plugin, SKU tier, autoscaling, observability.
2. **How services authenticate to Azure resources inside the cluster** — without secrets, without rotation, with one DefaultAzureCredential line of code that works identically on a developer laptop and in AKS.
3. **What base image services build from** — security posture, supply-chain control, and operational debugging.

These three decisions are interconnected: chiseled images need Workload Identity (no shell to set env vars at runtime); Workload Identity needs OIDC issuer enabled on the cluster (an AKS feature flag); the cluster sizing has to keep the image size and pull bandwidth manageable.

---

## Decisions

### Decision 1 — AKS cluster shape

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Cluster SKU tier** | `Free` in dev, `Standard` in prod | Free has no SLA but costs $0. Standard adds 99.95% SLA for ~$73/month — pure waste in a single-developer dev cluster. Production needs the SLA. Per-environment tier selection is a deliberate Well-Architected cost-pillar pattern. |
| **Node pools** | Two — `system` (tainted `CriticalAddonsOnly`) + `user` | Clean separation: CoreDNS, metrics-server, Container Insights agent live on `system`; app pods naturally land on `user` because they don't carry the matching toleration. Independent scaling of each pool. |
| **VM size (dev)** | `Standard_B2s` on both pools | Burstable B-series at ~$31/mo/node. Burst credits are fine for stateless web apps. Dev decision documented at the resource level in `main.tf`. **Production overrides to D-series** (e.g., `D4s_v5`) for predictable steady-state CPU. |
| **Autoscaler** | System 1–2, User 1–3 | One node per pool is enough at idle. User pool's 3-node cap accommodates the full 8-service fleet at ~150 MiB per pod plus headroom. |
| **Network plugin** | Azure CNI | One IP per pod (not per node, as in kubenet). Pods can be addressed directly from private endpoints — Cosmos and Service Bus traffic stays on the Azure backbone. /22 AKS subnet (1019 usable IPs) accommodates the dev growth path. |
| **Network policy** | Calico | Enables `NetworkPolicy` resources. Cannot be added after cluster creation; turning it on at create is forward-proofing. |
| **AKS API server** | Public (Free tier limitation) | Private AKS requires Standard tier. Public + RBAC + Azure AD integration is acceptable for dev. |
| **Image pulls** | AcrPull on the kubelet identity | Granting to the cluster identity is the most common AKS gotcha; the actual image puller is the kubelet identity. Module gets it right. |
| **Observability** | Container Insights → existing Log Analytics workspace | Reuse the workspace from Week 5. Managed-identity auth, no shared keys. |
| **Estimated dev cost** | ~$90/month running 24/7 | Destroy-when-idle pattern documented in DevelopmentGuide §7.10 brings this to ~$0. |

### Decision 2 — Workload Identity for secret-less Azure access

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Cluster flags** | `oidc_issuer_enabled = true` + `workload_identity_enabled = true` | Free to enable. The two flags together expose the OIDC issuer URL and project service-account tokens into pods. |
| **Federation scope (Week 7)** | Products only | Matches what's actually deployed. Pre-creating identities for the other 7 services would create Azure objects with no benefit. Adding more in Weeks 8–9 is a clean extension — see "Adding more service identities" comment in `modules/identity/main.tf`. |
| **Identity type** | User-Assigned Managed Identity (UAMI) | Required for federation — system-assigned identities have a lifecycle tied to a host resource and can't be pre-created. UAMIs are independent Azure resources with stable client IDs. |
| **Federation pattern** | One UAMI per service, one federated credential per UAMI, subject = `system:serviceaccount:<ns>:<sa>` | Standard pattern. Each service's identity is independent — a compromise of one doesn't propagate. |
| **Code change required in services** | **None** | Application code already uses `DefaultAzureCredential`. The credential source is `AzureCliCredential` locally and `WorkloadIdentityCredential` in AKS — same line of code, different provider in the chain. This is the entire point. |

The full identity chain from pod to Azure resource is diagrammed in DevelopmentGuide §7.4 and in the teaching comments in `modules/identity/main.tf`.

### Decision 3 — Custom hardened base image (chiseled)

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Base image** | `mcr.microsoft.com/dotnet/aspnet:9.0-noble-chiseled` | No shell, no apt, no coreutils. Image size ~115 MB vs ~220 MB for the standard runtime. Attack surface is the .NET runtime + OpenSSL + ca-certificates only. |
| **Published as** | `acrantkartdev.azurecr.io/antkart-base:9.0` | One organisation-owned base image in ACR. All 8 services FROM this. |
| **Why an ACR-hosted base, not direct from mcr.microsoft.com** | Supply-chain control, faster AKS pulls (Azure backbone), single hardening surface, target for Week 11 admission policy (Trivy scan + signed-digest gating). |
| **Non-root user** | UID 1654 (chiseled image's default) | Enforced by pod security context `runAsNonRoot: true` in the Helm chart. Kubelet refuses to start pods running as root. |
| **Globalization** | Invariant mode (`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true`) | Chiseled images don't ship ICU. AntKart formatting (currency literals like `₹{X:N2}`) works under invariant mode. Per-service override possible if any service later needs locale-aware formatting. |
| **Debugging trade-off** | No shell in the running container → use `kubectl debug` ephemeral containers | `kubectl exec -- /bin/sh` does not work. Modern Kubernetes pattern is to attach an ephemeral debug container with a full toolchain that shares the pod's PID namespace. Documented in DevelopmentGuide §7.7. |

---

## Considered Alternatives

### Alternative 1 — Service-account secrets instead of Workload Identity

Mount Azure SP credentials as Kubernetes Secrets, set `AZURE_CLIENT_SECRET` env var on each pod.

**Rejected** because:
- Secrets must be rotated. Workload Identity has zero-rotation by design.
- Secrets can leak into logs, image layers, etcd backups, and developer machines via `kubectl get secret -o yaml`.
- `DefaultAzureCredential` already abstracts this — Workload Identity is the modern path, secrets are the legacy path.

### Alternative 2 — Standard non-chiseled base image

`mcr.microsoft.com/dotnet/aspnet:9.0` (full Debian-based runtime image, ~220 MB).

**Rejected** because:
- Larger attack surface (bash, apt, coreutils all reachable from a compromised process).
- Larger image size means slower AKS cold starts and higher ACR egress costs at scale.
- `kubectl exec` shell access is convenient but encourages bad operational habits ("I'll just SSH in and fix it").

**Trade-off accepted:** debugging is harder. `kubectl debug` ephemeral containers are the documented escape hatch.

### Alternative 3 — Single node pool

One pool, app and system pods mixed.

**Rejected** because:
- Resource contention between CoreDNS and a hot app pod can cripple the cluster.
- Cannot scale or upgrade app workloads without affecting kube-system.
- Spot VMs (future cost optimization) become safe to add as a third pool only if system stays on regular VMs.

### Alternative 4 — `kubenet` network plugin

One IP per node, pods NAT'd to the node IP.

**Rejected** because:
- Pods cannot reach Azure private endpoints directly (NAT collapses to one IP, breaking source-IP-sensitive routing).
- NSG rules can't be applied to pod traffic — visibility is lost at the node boundary.
- Production AntKart will rely on private endpoints to Cosmos/Service Bus; Azure CNI is the only plugin that makes that work cleanly.

### Alternative 5 — Standard SKU tier in dev

`sku_tier = "Standard"` everywhere.

**Rejected** because:
- $73/month for an SLA that doesn't matter in a single-developer dev cluster destroyed nightly.
- The deliberate per-environment tier selection is itself a learning artifact — the Well-Architected Framework's cost pillar in practice.

---

## Consequences

**Operationally:**
- The single command sequence to spin up and tear down AKS is short. Destroy when idle.
- Debugging requires `kubectl debug --image=...`, not `kubectl exec -- sh`. Cost of the security posture.
- Adding a new service's Workload Identity is a four-step pattern (create UAMI → grant roles → create federated credential → set chart values). The pattern is documented in `modules/identity/main.tf` comments and DevelopmentGuide §7.8.

**Architecturally:**
- Application code is unchanged. The same `DefaultAzureCredential` runs locally with `az login` and in AKS with Workload Identity — the difference is which credential provider in the chain succeeds.
- The custom base image becomes the platform team's hardening surface. Week 11 adds Trivy scanning and admission policy on top of it.
- The Free SKU tier is a per-environment choice, not a permanent design. Prod overrides to Standard.

**Financially:**
- Dev cluster ≈ $90/month if left running; ~$0 with destroy-when-idle.
- Total dev environment (AKS + ACR + Cosmos serverless + Service Bus Standard + Key Vault + Log Analytics) ≈ $105–115/month running, ~$15–20 when AKS is torn down.
