# antkart-service — Helm Chart

One reusable chart that deploys any of the 8 AntKart microservices. Per-service overrides live in [`charts/values/<service>.yaml`](../values/).

## What the chart renders

| Template | When | Purpose |
|----------|------|---------|
| `serviceaccount.yaml` | Always | Kubernetes ServiceAccount; carries the `azure.workload.identity/client-id` annotation when WI is enabled |
| `deployment.yaml`     | Always | Pod template, security context, probes, resources, env, named ports |
| `service.yaml`        | Always | ClusterIP exposing the pod inside the cluster |
| `hpa.yaml`            | Only when `autoscaling.enabled: true` | HorizontalPodAutoscaler v2 on CPU utilization |
| `_helpers.tpl`        | n/a   | Naming + label helpers |

## Per-service status (Week 7)

| Service | Values file | Status | Workload Identity |
|---------|-------------|--------|-------------------|
| AK.Products      | [`values/products.yaml`](../values/products.yaml)         | **Active — deployed this week**    | ENABLED  |
| AK.Order         | [`values/order.yaml`](../values/order.yaml)               | Not yet deployed | DISABLED (placeholder) |
| AK.Payments      | [`values/payments.yaml`](../values/payments.yaml)         | Not yet deployed | DISABLED (placeholder) |
| AK.Notification  | [`values/notification.yaml`](../values/notification.yaml) | Not yet deployed | DISABLED (placeholder) |
| AK.ShoppingCart  | [`values/shoppingcart.yaml`](../values/shoppingcart.yaml) | Not yet deployed | DISABLED |
| AK.UserIdentity  | [`values/useridentity.yaml`](../values/useridentity.yaml) | Not yet deployed | DISABLED (uses ClientSecret) |
| AK.Gateway       | [`values/gateway.yaml`](../values/gateway.yaml)           | Not yet deployed | DISABLED |
| AK.Discount      | [`values/discount.yaml`](../values/discount.yaml)         | Not yet deployed | DISABLED |

The 7 placeholder files exist to prove the chart template generalizes correctly. They are safe to `helm template` (renders YAML to stdout) but should not be `helm install`-ed until each service's managed identity is created and federated — see each file's header for the prerequisites.

## Install Products (Week 7)

```bash
# Federated client ID — fetched from the identity Terraform module's state.
PRODUCTS_CLIENT_ID=$(cd infrastructure/environments/dev/identity && terragrunt output -raw products_client_id)

# Entra app registration values for JWT validation.
AZURE_AD_CLIENT_ID="<api-app-client-id>"
AZURE_AD_AUDIENCE="api://${AZURE_AD_CLIENT_ID}"

helm install ak-products charts/antkart-service \
  --namespace ak-products --create-namespace \
  -f charts/values/products.yaml \
  --set image.tag=$(git rev-parse --short HEAD) \
  --set workloadIdentity.clientId=${PRODUCTS_CLIENT_ID} \
  --set-string "env[*].name=AzureAd__ClientId,env[*].value=${AZURE_AD_CLIENT_ID}" \
  --set-string "env[*].name=AzureAd__Audience,env[*].value=${AZURE_AD_AUDIENCE}"
```

(The exact env-var injection commands are spelled out properly in DevelopmentGuide §7.6.)

## Validate before installing

```bash
# Render the chart locally without contacting the cluster — catches template errors.
helm template ak-products charts/antkart-service -f charts/values/products.yaml \
  --set image.tag=test --set workloadIdentity.clientId=00000000-0000-0000-0000-000000000000

# Lint the chart for Helm best-practice violations.
helm lint charts/antkart-service -f charts/values/products.yaml
```

## Uninstall

```bash
helm uninstall ak-products --namespace ak-products
kubectl delete namespace ak-products
```
