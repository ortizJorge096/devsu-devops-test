# ADR 004 — Single-AZ deployment (Free Tier trade-off)

## Status
Accepted — 2026-05-21

## Context
The brief asks for a Kubernetes deployment with horizontal scalability
inside the AWS Free Tier. Multi-AZ high availability is a desirable
production property but every viable AWS-native option **breaks Free
Tier**:

| Option | Multi-AZ? | Free Tier? | Cost/mo after |
|---|---|---|---|
| EKS managed node groups across 2 AZs | Yes | **No** — $73/mo control plane | $80+ |
| ASG (2 nodes, 2 AZs) + NLB | Yes | **No** — NLB $16/mo | $30+ |
| 2× t3.micro running k3s server+agent | Partial (no control-plane HA) | Yes (1500 hrs/mo) | $15 |
| **1× t3.micro running k3s single-node (current)** | **No** | **Yes** | **$0** |

## Decision
Run a **single-node k3s on one EC2 t3.micro in one AZ** for the demo.
The infrastructure module (`terraform/modules/network`) provisions
**two public subnets across two AZs** so future migration is just a
matter of changing the EC2 sizing or wrapping it in an ASG — the
network is already multi-AZ-ready.

## Consequences

Trade-offs accepted today
- An AZ outage takes the service down. AWS rarely loses a whole AZ,
  but it does happen (notably us-east-1c in Dec 2021).
- No control-plane HA: if the t3.micro dies, k3s + its embedded SQLite
  datastore die with it. The Elastic IP + auto-recovery alarm reduce
  MTTR but don't make it zero.
- Within the node, **horizontal scaling still works**: HPA scales pods
  2..6 based on CPU/memory. So "horizontal scalability" (the test
  requirement) is satisfied at the pod level.

What is already prepared for the migration
- VPC has subnets in `us-east-1a` and `us-east-1b`.
- The K8s Deployment has `topologySpreadConstraint` set so pods
  spread across nodes when there are multiple.
- The k3s registry config + ECR credential helper + image
  manifests are AZ-agnostic — same configuration applies whether
  you scale to 2 nodes or 200.

## Migration paths

### Path A — Stay on k3s, add a worker (cheapest)
- Add a second `aws_instance` in the second public subnet.
- Install k3s in agent mode pointing at the existing server.
- ASG + Launch Template lets it auto-replace.
- Add a NLB or ALB for traffic distribution (loses Free Tier).
- **Cost**: ~$15-30/mo.

### Path B — Migrate to EKS (production-grade)
- Replace `ec2-k3s` module with an `eks` module + managed node group.
- Same Kustomize manifests apply unchanged (overlay `prod` only needs
  `ingressClassName: alb` instead of `traefik`).
- **Cost**: ~$80/mo (EKS control plane + 2× t3.small + ALB).

### Path C — Hybrid (use ECS Fargate for the app)
- Replace k3s with ECS Fargate behind ALB. No Kubernetes but multi-AZ
  out of the box.
- Loses the "K8s deploy" requirement of the test, so this would only
  make sense post-test for a real production migration.

## Decision review trigger
Revisit this ADR if:
- The workload moves beyond demo/educational use.
- Free Tier eligibility expires (12 months from account creation).
- A real SLA is committed (>99.5%).
