# Devsu — DevOps Technical Test

**Author:** Jorge Alexander Caballero Ortiz · `jcaballeroo96@gmail.com`
**Stack target:** Node.js (Express + Sequelize + SQLite) → Docker → Kubernetes → Terraform on AWS Free Tier
**CI/CD:** GitHub Actions · Registry: **Amazon ECR (via OIDC, no static keys)** · IaC: Terraform 1.10+

---

## 1. What this repo delivers

| Requirement (test brief) | Where it lives |
|---|---|
| Dockerize the app (env vars, run user, port, healthcheck) | `app/Dockerfile`, `app/.dockerignore` |
| Pipeline as code (build, unit tests, static analysis, coverage, build & push) | `.github/workflows/ci-cd.yml` |
| Vulnerability scan (optional) | Trivy job in the same workflow |
| Deploy on Kubernetes (≥ 2 replicas, horizontal scaling, ConfigMap, Secret, Ingress) | `k8s/base/` + overlays |
| K8s deploy added to the pipeline | `deploy` job — runs on a **self-hosted runner colocated on the k3s EC2** |
| README with diagrams | this file + `docs/` |
| **Extra: IaC on a public cloud** | `terraform/` (S3 state + VPC + ECR + GitHub OIDC + EC2/k3s + CloudWatch) |
| **Extra: TLS / DNS / etc. for production** | **implemented** — cert-manager + Let's Encrypt + nip.io on the prod overlay (`k8s/overlays/prod/tls-patch.yaml`, ADR-005 + ADR-008) |

---

## 2. Architecture

### 2.1 Component overview

```mermaid
flowchart LR
  subgraph Dev["Developer workflow"]
    DEV[Developer] -- git push --> GH[GitHub Repo]
  end

  subgraph CI["GitHub Actions (ubuntu-latest)"]
    GH --> LINT[Lint] --> TEST[Test + Coverage]
    TEST --> SAST[njsscan + gitleaks]
    SAST --> BUILD[Build & Push image to ECR via OIDC]
    BUILD --> SCAN[Trivy scan]
    SCAN --> VALID[Validate K8s with kubeconform]
    VALID --> DEPLOY[Deploy job - self-hosted runner]
  end

  subgraph AWS["AWS account (Free Tier-ish)"]
    direction TB
    ECR[(Amazon ECR)]
    EIP[Elastic IP]
    subgraph EC2["EC2 t3.micro - SPOT one-time - Amazon Linux 2023"]
      direction TB
      RUNNER[gh self-hosted runner - systemd]
      TIMER[refresh-ecr-token.timer - 8h]
      CERTMGR[cert-manager + ClusterIssuers]
      K3S[k3s single-node cluster]
      subgraph NS_PROD["namespace: demo-devops (prod) - TLS via Let's Encrypt"]
        DEP[Deployment x1 replica]
        SVC[Service ClusterIP]
        ING[Ingress / traefik - tls: nip.io]
        CM[ConfigMap]
        SEC[Secret]
        PDB[PodDisruptionBudget]
        NP[NetworkPolicy]
      end
      subgraph NS_DEV["namespace: demo-devops-dev (dev)"]
        DEP2[Deployment x2 replicas]
        HPA2[HPA 2..3]
        SVC2[Service ClusterIP]
        ING2[Ingress / traefik]
      end
      DEP --> SVC --> ING
      DEP2 --> SVC2 --> ING2
      CM --> DEP
      SEC --> DEP
      HPA2 -. scales .-> DEP2
      TIMER -. refreshes ECR auth .-> K3S
    end
    EIP --> EC2
    S3[(S3 - TF state - use_lockfile)]
    OIDC[IAM OIDC role GH->AWS]
    SNS[(SNS - CloudWatch alarms)]
  end

  ECR -. image pull via instance profile token .-> K3S
  CI -- "docker push (OIDC)" --> ECR
  DEPLOY -- "runs ON the EC2" --> RUNNER
  RUNNER -- "kubectl apply -k" --> K3S
  CI -. "AssumeRoleWithWebIdentity (OIDC)" .-> OIDC
  CERTMGR -. ACME HTTP-01 .-> LE[(Let's Encrypt)]
  CERTMGR -- "Certificate -> Secret" --> ING
  USER[Internet user] -- HTTPS green padlock --> EIP
  K3S -. mem/disk metrics .-> SNS
```

### 2.2 Pipeline

```mermaid
flowchart TD
  PR[Push / PR] --> L[Lint - ESLint]
  L --> T[Test + Coverage - Jest]
  L --> S[SAST - njsscan + gitleaks]
  L --> V[Validate K8s - kubeconform on local+dev+prod overlays]
  T --> B[Build & Push - Amazon ECR via OIDC]
  S --> B
  B --> C[Trivy image scan - SARIF to GH Security]
  V --> D[Deploy to k3s - self-hosted runner]
  C --> D
  D -. develop -> dev .-> ENV_DEV[demo-devops-dev / EIP]
  D -. main    -> prod .-> ENV_PROD[demo-devops / EIP]
```

---

## 3. Repository layout

```
.
├── app/                         # Node.js app + Dockerfile
│   ├── Dockerfile               # multi-stage, non-root, HEALTHCHECK, dumb-init
│   ├── .dockerignore
│   ├── .eslintrc.json
│   ├── .env.example
│   ├── index.js                 # + /health endpoint, PORT from env
│   ├── index.test.js            # + health test
│   ├── package.json             # scripts: test:coverage, lint
│   └── ...
├── k8s/                         # Kustomize base + overlays
│   ├── base/                    # Deployment, Service, Ingress, ConfigMap,
│   │                            # Secret, HPA, PDB, NetworkPolicy, Namespace
│   └── overlays/
│       ├── local/               # minikube / docker-desktop, ingress-nginx,
│       │                        # 2 replicas + HPA 2..6 (brief evidence)
│       ├── dev/                 # k3s on EC2, traefik, 2 replicas + HPA 2..3
│       └── prod/                # k3s on EC2, traefik, 1 replica (ADR-006)
├── terraform/
│   ├── bootstrap/               # S3 state bucket (Terraform 1.10 use_lockfile)
│   ├── modules/
│   │   ├── network/             # VPC + public subnets across two AZs
│   │   ├── ecr/                 # private ECR repo + lifecycle policy
│   │   ├── github-oidc/         # OIDC provider + IAM role for GH Actions
│   │   ├── ec2-k3s/             # EC2 Spot t3.micro + k3s userdata + EIP
│   │   └── monitoring/          # CloudWatch alarms (CPU/mem/disk) + SNS
│   └── environments/dev/        # composition: network+ECR+OIDC+EC2/k3s+monitoring
├── scripts/
│   ├── local-deploy.sh          # build + apply local overlay on minikube
│   ├── k8s-deploy.sh            # manual apply on the k3s host (break-glass)
│   └── port-forward.sh          # expose svc on localhost without ingress
├── .github/workflows/
│   └── ci-cd.yml                # main pipeline (lint, test, SAST, build, scan, deploy)
├── docs/
│   └── decisions/               # ADRs (architecture decision records)
├── .gitleaks.toml
├── LICENSE
└── README.md
```

---

## 4. Quick start — local

### 4.1 Run the app

```bash
cd app
cp .env.example .env
npm ci
npm start
# -> Server running on port 8000
curl http://localhost:8000/health
curl http://localhost:8000/api/users
```

### 4.2 Run the tests + coverage

```bash
cd app
npm ci
npm run test:coverage
```

### 4.3 Build the Docker image

```bash
cd app
docker build -t demo-devops-nodejs:dev .
docker run --rm -p 8000:8000 demo-devops-nodejs:dev
curl http://localhost:8000/health
```

### 4.4 Deploy on local Kubernetes (minikube / docker-desktop)

The repo ships `scripts/local-deploy.sh` that does the build + apply +
rollout wait in one go:

```bash
# Optional: minikube with ingress addon
minikube start --addons=ingress

# One-shot deploy (uses minikube's docker daemon if minikube is running)
scripts/local-deploy.sh

# Add hosts entry (Linux/mac):
echo "$(minikube ip) demo-devops.local" | sudo tee -a /etc/hosts

# Hit the app:
curl http://demo-devops.local/health
curl http://demo-devops.local/api/users
```

> On docker-desktop the ingress lives on `127.0.0.1`. Either point your
> hosts file at `127.0.0.1 demo-devops.local`, or use the port-forward
> helper: `scripts/port-forward.sh`.

---

## 5. Quick start — AWS deploy

### 5.1 Prerequisites

- AWS account (ideally with Free Tier still active — see §5.3 about Spot).
- AWS CLI v2 configured (`aws configure`) — needs `iam`, `s3`, `ec2`, `ecr`, `sns` permissions for the bootstrap user.
- Terraform **>= 1.10** (for native S3 state locking).
- A public GitHub repo with this code.
- A GitHub fine-grained PAT with **`Administration: read+write`** on the repo (used once at boot to register the self-hosted runner — never stored after that).

### 5.2 Apply order

```bash
# 1) Bootstrap state bucket (one-time, uses LOCAL state)
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=devsu-devops-tfstate-$(aws sts get-caller-identity --query Account --output text)"
# Note the output: state_bucket_name

# 2) Wire backend.tf in dev env with that bucket name
cd ../environments/dev
# Edit backend.tf -> set bucket = "<state_bucket_name from step 1>"

# 3) Configure variables (do NOT commit terraform.tfvars)
cp terraform.tfvars.example terraform.tfvars
# edit github_owner, github_repo, alarm_email, github_token (PAT)

# 4) Plan & apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Outputs you'll need:
#   app_url             -> http://<EIP>/api/users
#   health_url          -> http://<EIP>/health
#   ssm_session_command -> shell on the node (break-glass only)
#   github_actions_role_arn -> put as AWS_ROLE_ARN secret in GH

# 5) Tear everything down when finished
terraform destroy
```

### 5.3 Cost profile

The EC2 instance is provisioned as **Spot, one-time** (`market_type = "spot"`,
`spot_instance_type = "one-time"`). This is documented in
`terraform/modules/ec2-k3s/main.tf`.

| Resource | Free Tier on-demand | Spot reality (this repo) |
|---|---|---|
| EC2 t3.micro · 1 instance | 750 hrs/mo free | **~$0.003/h ≈ $2/mo** — Spot is NOT covered by Free Tier |
| EBS gp3 · 20 GB | 30 GB free | $0 during Free Tier, ~$1.60/mo after |
| Elastic IP (attached) | free | free while attached |
| ECR Private (~150 MB) | 500 MB free | $0.10/GB/mo after |
| S3 (state) | 5 GB free | first 5 GB free always for new buckets |
| IAM, OIDC, SSM, SNS (low volume) | always free | always free |
| **Total inside Free Tier window** | **~$2/mo** (Spot premium) | |
| **Total after Free Tier** | | **~$3–4/mo** (Spot is the cheap path) |

> Trade-off: Spot is ~70% cheaper than on-demand outside Free Tier, but
> AWS can reclaim the instance with a 2-minute warning. The user-data
> script bootstraps k3s + the app from scratch, so re-running
> `terraform apply` rebuilds the cluster in ~5–7 minutes. For a demo this
> is acceptable; for a production workload, switch
> `spot_instance_type = "persistent"` (or move to on-demand).

> Always `terraform destroy` once the test is reviewed to avoid the small
> recurring Spot + EBS bill.

---

## 6. Design decisions (highlights)

| Decision | Why |
|---|---|
| **k3s on t3.micro** instead of EKS | EKS control plane is $73/mo flat — not Free Tier. k3s is CNCF-certified, single binary, fits 1 GiB RAM. (ADR-001) |
| **Spot, one-time lifecycle** | Cheapest sustainable cost outside Free Tier (~70% off). The cluster is fully reproducible from user-data, so a reclaim is a "re-apply" away. |
| **Amazon ECR** as primary registry | Coherent with AWS-native infra: same IaC provisions the registry AND the IAM/OIDC permissions to push from CI / pull from the EC2 instance profile. No static keys, no PATs. (ADR-003) |
| **OIDC GH → AWS** instead of static keys | Short-lived STS tokens, scoped per repo+branch+environment, no `AWS_ACCESS_KEY_ID` secret to leak. |
| **ECR token refresh via systemd timer** | k3s' containerd doesn't honor docker credential helpers in `registries.yaml`. The user-data writes a `refresh-ecr-token.sh` script + a `.timer` unit that re-fetches a 12h ECR token every 8h using the instance profile. No `imagePullSecrets`, no CronJob inside the cluster. |
| **Self-hosted runner on the k3s EC2** | The `deploy` job runs ON the cluster's host — `kubectl apply` is local, no SSM Send-Command, no SSH, no nested heredocs, no OIDC AWS round-trip from the runner. The PAT only lives on the box during the initial `config.sh` and is scrubbed from the boot log. |
| **Terraform 1.10 native S3 locking** (`use_lockfile`) | Drops DynamoDB requirement → fewer resources to maintain and to fit inside Free Tier. (ADR-002) |
| **Kustomize base + overlays** (no Helm) | Lighter for a single app, declarative, GitOps-friendly, plays well with `kustomize edit set image` from CI. |
| **Non-root + read-only rootfs + drop ALL caps** | Pod Security Standard "restricted" is enforced at namespace admission. |
| **Multi-stage Dockerfile + dumb-init** | Final image ~150 MB; PID 1 forwards SIGTERM → graceful node shutdown. |
| **Dev: HPA 2..3 / Prod: HPA 1..1** | Brief asks for ≥2 replicas + horizontal scaling — proven on `dev` and `local`. Prod stays at 1 to leave headroom for the colocated runner. (ADR-006, amended) |
| **TLS on prod via cert-manager + Let's Encrypt + nip.io** | Real green-padlock cert at `https://demo-devops.<eip>.nip.io/api/users` with no domain registration and $0 cost. cert-manager runs cluster-wide; only the prod overlay's Ingress is annotated. Dev keeps traefik's self-signed cert to save RAM on the t3.micro. (ADR-005 + ADR-008) |
| **PodDisruptionBudget** | Voluntary disruptions (node drain, upgrades) never take all pods down. |
| **NetworkPolicy** | Default-deny ingress; only the ingress controller and same-namespace pods can talk to the app. |
| **Trivy + njsscan + gitleaks** | Image CVEs, JS-specific SAST, and secret scanning before push. |
| **CloudWatch agent + SNS alarms** | Memory + disk + CPU alarms wired to an email subscription; userdata.log shipped to CloudWatch Logs. |

ADRs (Architecture Decision Records) live in `docs/decisions/`.

---

## 7. Secrets & variables to configure in GitHub

The deploy job runs on a **self-hosted runner** that lives on the EC2
instance itself (registered automatically by the Terraform user-data
using your PAT). The runner has cluster-admin on the local k3s kubeconfig
and a pre-authenticated containerd — so the `deploy` job needs **no AWS
credentials at all**. The only AWS-touching jobs are `build-push` and
`image-scan`, which assume the OIDC role.

### 7.1 Repository secrets (shared by all environments)

| Secret | Used by | What it is |
|---|---|---|
| `GITHUB_TOKEN` | every job | provided automatically by Actions |

### 7.2 Per-environment secrets + variables

Create two GitHub Environments: **`production`** (branch: `main`) and **`dev`** (branch: `develop`).
Add these to **each** environment:

| Name | Type | What it is |
|---|---|---|
| `AWS_ROLE_ARN` | **Secret** | `terraform output -raw github_actions_role_arn` — the OIDC role CI assumes for ECR push + Trivy scan |
| `APP_URL` | **Variable** | `http://<Elastic-IP>/api/users` — shown as the environment link in the Actions UI |

> No `EC2_HOST` / `EC2_USER` / `EC2_SSH_KEY` / SSM IDs are required — the
> `deploy` job runs on the cluster host through the self-hosted runner.

### 7.3 Branch → Environment mapping

| Branch | GitHub Environment | K8s namespace | K8s overlay |
|---|---|---|---|
| `main` | `production` | `demo-devops` | `k8s/overlays/prod` |
| `develop` | `dev` | `demo-devops-dev` | `k8s/overlays/dev` |

---

## 8. Helper scripts (`scripts/`)

| Script | Purpose |
|---|---|
| `scripts/local-deploy.sh` | Build the image inside the local docker daemon (minikube-aware) and apply the `local` overlay. Idempotent — re-run after code changes. |
| `scripts/k8s-deploy.sh` | Manual / break-glass equivalent of the CI `deploy` job. Run from a shell on the k3s host: `bash scripts/k8s-deploy.sh <overlay> <namespace> <image> <branch>`. |
| `scripts/port-forward.sh` | `kubectl port-forward` against `svc/demo-devops`. Useful when there's no ingress controller available locally. Override defaults with `NAMESPACE=` / `LOCAL_PORT=` env vars. |

---

## 9. Pipeline evidence (what to share with the reviewer)

After pushing to `main` for the first time, share with the reviewer:

1. URL to the `CI/CD` workflow run — **all jobs green**.
2. Screenshot of the ECR repository in the AWS console showing the pushed image tags (`sha-<hash>`, `latest`, `main`).
3. URL to the **Security → Code scanning** tab where Trivy + njsscan SARIFs appear.
4. The Terraform output `app_url` once `terraform apply` finishes — that's the **public endpoint** asked for in the brief.
5. Output of `kubectl -n demo-devops-dev get deploy,hpa,pdb,svc,ingress` to demonstrate the 2-replica + HPA + PDB setup on the dev overlay.
6. `curl -v https://demo-devops.<eip>.nip.io/api/users` from any laptop — the TLS handshake should show a Let's Encrypt-issued cert (subject `CN=demo-devops.<eip>.nip.io`, issuer `R10/R11/E1/E5`). No `--insecure` flag needed. (Terraform output `app_url_https`.)

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `ImagePullBackOff` on k3s | `/etc/rancher/k3s/registries.yaml` is missing or stale. `sudo /usr/local/sbin/refresh-ecr-token.sh` re-mints the auth block and HUPs k3s. Also check `journalctl -u refresh-ecr-token.timer`. |
| Pod CrashLoopBackOff with sqlite errors | The `data/` emptyDir didn't mount as writable — check `securityContext.fsGroup` and `readOnlyRootFilesystem: true` + writable volume. |
| `terraform init` complains about lock | You're on Terraform < 1.10; upgrade or remove `use_lockfile = true` from `backend.tf` (and add DynamoDB). |
| EC2 has no kubectl access | Open a shell via the Terraform output `ssm_session_command`, then `sudo cat /etc/rancher/k3s/k3s.yaml`. To use it from your laptop, rewrite `server: https://<EIP>:6443`. |
| Healthcheck fails inside Docker | The image uses `wget`; if you replace the base image, install `wget` or switch to `curl --fail`. |
| `Deploy` job fails: "no runner matching labels [self-hosted, k3s-deploy]" | The EC2 finished `user-data` but didn't register. Check `journalctl -u actions.runner.*` on the box. Most common cause: `github_token` was missing or expired at `terraform apply` time. |
| Spot reclamation message in AWS console | AWS reclaimed the instance. Re-run `terraform apply` — the user-data brings k3s + the app back in ~5–7 minutes. A new EIP triggers a new Let's Encrypt order (within the rate limit). |
| Out-of-memory on dev pod | t3.micro is tight with 2 replicas + the runner. Either turn off `cloudwatch_agent_config` or move to `t3.small` (see ADR-006 migration path). |
| TLS handshake fails on prod (`SSL_ERROR_NO_CYPHER_OVERLAP` / NET::ERR_CERT_AUTHORITY_INVALID) | cert-manager hasn't issued the cert yet. `kubectl -n demo-devops describe certificate demo-devops-tls` shows the status. Most common: the ACME HTTP-01 challenge failed because the nip.io FQDN doesn't resolve back to this EIP (check `dig demo-devops.<eip>.nip.io`). Until issuance succeeds, traefik serves its self-signed default — same UX as dev. |
| Let's Encrypt rate-limit error in cert-manager logs | nip.io shares one eTLD+1 across all users. Switch the Ingress annotation to `letsencrypt-staging` (already provisioned) and re-test; switch back after 7 days. ADR-008 §"Migration paths" covers this. |

---

## 11. License

MIT — see `LICENSE`.
