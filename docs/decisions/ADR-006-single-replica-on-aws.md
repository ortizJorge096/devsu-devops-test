# ADR 006 — Single replica on AWS overlays (t3.micro RAM trade-off)

## Status
Accepted — 2026-05-23

## Context
The brief requires "**at least two replicas and horizontal scaling**" for the
Kubernetes deployment. The base K8s manifests honor this: `Deployment.replicas:
2` and an HPA scaling `minReplicas: 2 → maxReplicas: 6` on CPU/memory.

The local overlay (`k8s/overlays/local`, targeted at minikube /
docker-desktop) keeps those defaults and is the **canonical proof** that the
requirement is satisfied — see `docs/local-deploy.md` for the evidence
(`kubectl get all,hpa`, screenshots, load test).

The brief explicitly allows local Kubernetes as the primary deployment
target ("**no se requiere que utilice un entorno público, puede utilizar
minikube/docker-desktop en un entorno local**"). The AWS deployment is
extra credit ("Puntos extra: Se darán puntos adicionales si crea la
infraestructura usando IaC en un proveedor público").

The AWS deployment is provisioned on a `t3.micro` (1 GiB RAM) — the Free
Tier choice documented in ADR-001. Empirical memory budget on this
instance, with the self-hosted GitHub Actions runner colocated (see
ADR-007):

| Component                                    | RAM    |
|---------------------------------------------|--------|
| Kernel + systemd + ssm-agent                | 180 MB |
| k3s control plane (apiserver + etcd + ...)  | 450 MB |
| traefik + CoreDNS + metrics-server          | 130 MB |
| containerd                                  |  50 MB |
| GitHub Actions runner (idle)                | 130 MB |
| App pod (1 × Node.js, real usage)           | 130 MB |
| **Subtotal idle**                           | **~1070 MB** |
| Runner during deploy (checkout + kustomize) | +180 MB |
| **Peak during deploy**                      | **~1250 MB** |

A second replica (2 × 130 MB) on top of that pushes the instance into
swap, and historically caused etcd / SSM Agent to become unresponsive —
matching the cascade of failures seen in earlier pipeline runs (#1..#14).

## Decision
On the **AWS overlays** (`k8s/overlays/dev` and `k8s/overlays/prod`):

- `Deployment.replicas: 1`
- `PodDisruptionBudget.minAvailable: 0` (otherwise rolling updates block
  because `minAvailable: 1` with `replicas: 1` is unsatisfiable)
- `HorizontalPodAutoscaler.minReplicas: 1`, `maxReplicas: 1` — the HPA
  resource is still present (reviewer can inspect it) but it does not scale.

The **local overlay** (`k8s/overlays/local`) is **untouched**:

- `Deployment.replicas: 2`
- `HorizontalPodAutoscaler.minReplicas: 2`, `maxReplicas: 6`
- This is where the brief's HA + horizontal-scaling requirement is met
  and demonstrated.

## Consequences

Pros
- The AWS deployment fits inside `t3.micro` Free Tier without OOM.
- The base + local overlay still proves the design supports 2..6 replicas
  with HPA on real metrics. Zero changes needed to that path.
- Trade-off is explicit and easy for the reviewer to verify (`grep replicas
  k8s/overlays/`).

Cons
- The AWS endpoint is not HA: a single pod restart means a brief 503 window.
- The HPA on AWS is decorative. If the demo received real load it would
  not scale up.

## Migration path
Two ways to "lift the cap" on AWS:

1. **Resize the EC2** to `t3.small` (2 GiB RAM, +$0.0104/hr, **not** Free
   Tier). Change `instance_type` in
   `terraform/modules/ec2-k3s/variables.tf` and revert the overlay patches
   to `replicas: 2`, `minAvailable: 1`, HPA `2..6`. ~30 min of work,
   ~$15/mo.

2. **Move the runner off the EC2**: install the GitHub Actions runner on a
   separate cheap instance (or use ephemeral runners), freeing ~150 MB on
   the k3s host. Combined with disabling the CloudWatch Agent
   (`cloudwatch_agent_config = false`) recovers ~230 MB total — enough
   for 2 replicas with a thinner margin. ~1 hour of work, $0/mo extra.

## Decision review trigger
Revisit when either:
- Free Tier eligibility expires (move to t3.small is cheap enough).
- Real load arrives (the HPA cap becomes a real constraint, not a
  documentation footnote).
