# ADR 006 — Replica strategy on AWS overlays (t3.micro RAM trade-off)

## Status
Amended (2) — 2026-05-24

History:
- **Original (2026-05-23)**: single replica on every AWS overlay,
  motivated by `t3.micro` (1 GiB RAM) Free Tier constraints.
- **Amendment 1 (2026-05-23)**: dev moved to 2 replicas + HPA 2..3 to
  honor the brief on the AWS path; prod stayed at 1 replica due to the
  same RAM ceiling.
- **Amendment 2 (2026-05-24)**: prod also moved to 2 replicas + HPA
  2..3, after both environments were upgraded from `t3.micro` to
  `t3.medium` (4 GiB RAM). This executes "Migration path §1" of this
  ADR — the RAM ceiling that justified single-replica prod is no
  longer the binding constraint.

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
instance, with the self-hosted GitHub Actions runner colocated:

| Component                                    | RAM     |
|---------------------------------------------|---------|
| Kernel + systemd + ssm-agent                | 180 MB  |
| k3s control plane (apiserver + etcd + ...)  | 450 MB  |
| traefik + CoreDNS + metrics-server          | 130 MB  |
| containerd                                  |  50 MB  |
| GitHub Actions runner (idle)                | 130 MB  |
| App pods (2 × Node.js, real usage)          | 260 MB  |
| **Subtotal idle (2 replicas)**              | **~1200 MB** |
| Runner during deploy (checkout + kustomize) | +180 MB |
| **Peak during deploy (2 replicas)**         | **~1380 MB** |

With 2 replicas the node sits a bit over the 1 GiB physical RAM and dips
into swap during deploys, but the workload tolerates it (no OOMKills in
the last 50 pipeline runs on the dev branch). 3 replicas pushed the node
into thrashing — the HPA cap on dev is therefore 3.

## Decision

### `k8s/overlays/dev`  (target: `develop` branch, namespace `demo-devops-dev`)

- `Deployment.replicas: 2`  — matches the brief's "≥ 2 replicas" rule.
- `PodDisruptionBudget.minAvailable: 1`  — keeps one pod serving during
  voluntary disruptions (node drain, rolling update) without blocking
  evictions the way `minAvailable: 2` would.
- `HorizontalPodAutoscaler.minReplicas: 2`, `maxReplicas: 3`  — horizontal
  scaling demonstrated, capped at 3 to stay below the t3.micro thrash line.

### `k8s/overlays/prod` (target: `main` branch, namespace `demo-devops`)

After Amendment 2: same shape as dev.

- `Deployment.replicas: 2` — matches the brief's "≥ 2 replicas" rule on
  the prod path too. No longer relies on dev/local as the canonical
  evidence.
- `PodDisruptionBudget.minAvailable: 1` — guarantees at least one pod
  serving during voluntary disruptions (node drains, rolling updates).
- `HorizontalPodAutoscaler.minReplicas: 2`, `maxReplicas: 3` — same
  conservative envelope as dev. Cap stays at 3 to leave headroom for
  the colocated runner (see ADR-007) and the k3s control plane on the
  `t3.medium`; lifting it requires either moving the runner off-box or
  bumping the instance size further (Migration path §3 below).

The prior config (replicas: 1, PDB.minAvailable: 0, HPA 1..1) is
preserved in git history (this file's revision pre-2026-05-24) for
auditability of the original t3.micro-era trade-off.

### `k8s/overlays/local`

Unchanged. `replicas: 2` + HPA `2..6` on real CPU/memory metrics: the
canonical evidence that the brief's HA + horizontal-scaling requirement is
satisfied.

## Consequences

Pros
- Dev overlay now matches the literal text of the brief (`≥ 2 replicas`
  + horizontal scaling alive on the AWS cluster).
- A single pod restart during a dev rolling update no longer takes the
  endpoint down — there's always at least one pod serving traffic.
- The base + local overlay still proves the design supports 2..6 replicas
  with HPA on real metrics. Zero changes needed to that path.

Cons
- The historical t3.micro RAM analysis (table above) is preserved for
  context but no longer reflects the running infrastructure — both
  environments are on `t3.medium`. The `mem_used_percent` CloudWatch
  alarm at 85% still applies but fires much less often.
- The HPA cap of 3 on both overlays is a documentation footnote rather
  than a real ceiling; raising it requires either evidence of sustained
  load above the current envelope or a re-cost of the t3.medium baseline.

## Migration path
Two ways to "lift the cap" on AWS overlays:

1. **Resize the EC2** to `t3.small` (2 GiB RAM, +$0.0104/hr, **not** Free
   Tier). Change `var.instance_type` in `terraform/environments/dev/` and
   revert the prod overlay to `replicas: 2`, `minAvailable: 1`, HPA
   `2..6`. ~30 min of work, ~$15/mo.

2. **Move the runner off the EC2**: install the GitHub Actions runner on a
   separate cheap instance (or use ephemeral runners), freeing ~150 MB on
   the k3s host. Combined with disabling the CloudWatch Agent
   (`cloudwatch_agent_config = false`) recovers ~230 MB total — enough
   for the prod overlay to also run 2 replicas comfortably. ~1 hour of
   work, $0/mo extra.

## Decision review trigger
Revisit when either:
- Free Tier eligibility expires (move to t3.small is cheap enough).
- Real load arrives (the HPA cap of 3 becomes a real constraint, not a
  documentation footnote).
- Pipeline runs start surfacing OOMKills on dev — at which point the
  fastest mitigation is moving the runner off-box.
