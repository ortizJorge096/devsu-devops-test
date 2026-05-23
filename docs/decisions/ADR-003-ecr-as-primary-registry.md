# ADR 003 — Amazon ECR as the primary container registry

## Status
Accepted — 2026-05-21 (supersedes the implicit GHCR-first design)

## Context
The initial CI/CD pipeline pushed images to GitHub Container Registry (GHCR)
while Terraform provisioned an Amazon ECR repository with lifecycle and
vulnerability-scan settings. The ECR repo was not consumed anywhere — an
incoherence: IaC stood up a resource that the rest of the system ignored.

## Decision
Use **Amazon ECR as the only container registry**.

- CI authenticates to AWS via GitHub OIDC (no static keys) using the IAM
  role provisioned by the `github-oidc` module, and pushes to ECR.
- The k3s node on EC2 pulls from ECR through `amazon-ecr-credential-helper`,
  which exchanges the EC2 instance profile for short-lived ECR tokens against
  IMDSv2 — no `imagePullSecrets`, no token refresh CronJob, no PATs to leak.
- Kubernetes manifests use an opaque image key (`devsu-devops-nodejs`) that
  the pipeline rewrites with `kustomize edit set image
  devsu-devops-nodejs=<ecr>/<repo>:<sha-tag>` before applying.

## Consequences

Pros
- Single source of truth: the same Terraform that creates the registry also
  wires the IAM permissions to push from CI and pull from the cluster.
- No human-managed PATs; every credential is short-lived (15 min STS for CI,
  12 h for the credential helper).
- Image stays in the same AWS region as the runtime, so pulls are fast and
  no egress fees apply.
- Coherent demo of "everything an app needs, in IaC".

Cons
- The pipeline requires AWS infrastructure to exist before the first push
  can succeed. Bootstrapping order: `terraform apply` → set the
  `AWS_ROLE_ARN` GitHub secret → push.
- Reviewers without access to the AWS account cannot browse the image
  catalogue. They still see the workflow run + SHA, and `terraform output
  app_url` exposes the deployed app publicly.
- ECR scan happens on push (free, native), but we keep Trivy in the
  pipeline for SARIF visibility in the GitHub Security tab.

## Alternatives considered
- **GHCR only**: simpler, no AWS dependency to push, image public for free.
  Rejected because ECR was already being provisioned and went unused — the
  larger goal of the exercise is to demonstrate AWS-native IaC.
- **Hybrid (push to both GHCR and ECR)**: best of both worlds for review
  visibility, but two pushes per build, more moving parts, and a second
  set of credentials. Rejected as overkill for a single-app demo.

## Migration note (if reverting)
Re-enable the previous `docker/login-action` step in the workflow, restore
the `ghcr_user` / `ghcr_token` Terraform variables and the userdata block
that creates a `docker-registry` Secret in the `demo-devops` namespace.
Both flows live cleanly side-by-side if needed.
