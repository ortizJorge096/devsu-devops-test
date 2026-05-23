# ADR 001 — k3s on EC2 instead of EKS

## Status
Accepted — 2026-05-21

## Context
The brief asks for a Kubernetes deployment and gives extra credit for
provisioning the infrastructure on a public cloud with IaC, while staying
inside the AWS Free Tier.

EKS would be the "default best practice" answer in a real workload, but
its control plane costs ~USD $73/mo flat. That is **not** Free Tier
eligible — the first day of provisioning already produces a bill.

## Decision
Run **k3s (single-node)** on an EC2 `t3.micro` (Amazon Linux 2023).

- k3s is CNCF-certified Kubernetes (full API parity for our needs:
  Deployments, Services, Ingress, HPA, ConfigMap, Secret).
- It ships with **traefik** as the ingress controller, **flannel** for
  CNI, and an embedded SQLite-backed datastore (no etcd to operate).
- The whole control plane + worker fits in ~512 MiB RAM on a t3.micro.
- userdata cloud-init installs k3s, kustomize, and applies the prod overlay.

## Consequences

Pros
- Free Tier for 12 months (`t3.micro` 750 hrs/mo + 30 GB EBS).
- Same `kubectl` UX as EKS — no app changes between local and cloud.
- HPA, NetworkPolicy, Ingress all work as in EKS.

Cons
- Single-node ⇒ no real HA. `topologySpreadConstraint` is a no-op.
- SQLite-backed datastore ⇒ losing the EBS volume = losing cluster
  state. Acceptable for a demo, not for prod.
- TLS termination via traefik but no ACME bootstrap by default.

## Migration path
The Kustomize overlays already separate `local` (ingress-nginx) from
`prod` (traefik). Moving to EKS means: change the overlay's
`ingressClassName` back to `nginx` (or `alb`), provision EKS via a new
Terraform module, and re-apply. No Dockerfile / app changes.
