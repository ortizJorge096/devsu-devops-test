# ADR 007 — Self-hosted GitHub Actions runner colocated on the k3s EC2

## Status
Accepted — 2026-05-23 (retroactive: decision was implemented in commit
`35a69c8`, "feat(ci-cd,tf): replace SSM-based deploy with self-hosted
runner"; this ADR backfills the rationale).

## Context

The CI/CD pipeline needs to apply Kustomize manifests against the k3s
cluster that lives on a single EC2 (see ADR-001). The pipeline runs on
GitHub-hosted `ubuntu-latest` runners, which sit outside the AWS account
and cannot reach the cluster directly — k3s' apiserver is only published
on the node's private interface, never exposed to the internet.

We need a transport for `kubectl apply` from the pipeline to the cluster.
Three options were evaluated during the move away from the original
SSM-based deploy:

| Option | How `kubectl apply` reaches k3s | Network egress | Extra services |
|---|---|---|---|
| **A — SSM Send-Command from GitHub-hosted runner** (original) | Pipeline calls `ssm:SendCommand` with a heredoc shell script that runs `kubectl apply` on the box | Pipeline → AWS STS (OIDC) → SSM → SSM Agent on EC2 | SSM Agent, SSM document permissions in the OIDC role, IAM scoping |
| **B — Bastion + SSH** | Pipeline SSHes into the EC2 and runs `kubectl apply` | Pipeline → SSH (port 22 open on the SG) → EC2 | SSH key management, SG rule for inbound 22, key rotation |
| **C — Self-hosted runner on the EC2** (chosen) | Pipeline job is dispatched onto a runner process living on the EC2; `kubectl` is local | GitHub → outbound long-poll from EC2 (no inbound port) | One systemd service, one PAT used once at registration |

The SSM-based path (option A) was the original implementation and worked,
but accumulated friction over ~10 commits of escalation: SSM's 100-char
comment limit, heredoc quoting bugs, IPC timeouts on long-running
commands (`fix(ci-cd): use FETCH_HEAD instead of origin/branch`,
`fix(ci-cd): run deploy via nohup to avoid SSM IPC timeout`,
`fix(ci-cd): extend SSM timeout to 900s and improve k3s readiness check`,
etc.). Every change to the deploy script required learning whether
shell-in-shell-in-shell escaping had been broken again. That signal —
constant escaping churn on a flow that should be `kubectl apply -f -` —
is what motivated this ADR.

## Decision

Run the pipeline's `deploy-dev` and `deploy-prod` jobs on a **self-hosted
GitHub Actions runner that lives on the k3s EC2 itself**, registered
automatically by the Terraform `user-data` script (see the
`ec2-k3s` module, `github_token` variable).

The runner is colocated in the same OS as k3s. Concretely:

- Runner process: systemd unit `actions.runner.<owner>-<repo>.<name>`
  installed by `actions/runner`'s `svc.sh install` script.
- Runner user: dedicated `ghrunner` UNIX account with `/home/ghrunner/.kube/config`
  pre-populated from `/etc/rancher/k3s/k3s.yaml` (cluster-admin on the
  local k3s).
- containerd auth: the EC2 instance profile already grants
  `AmazonEC2ContainerRegistryReadOnly`, plus the periodic
  `refresh-ecr-token.timer` keeps `/etc/rancher/k3s/registries.yaml`
  fresh. The runner inherits that — no `imagePullSecrets`, no docker
  login from CI.
- Runner labels: `self-hosted,linux,x64,k3s-deploy,k3s-<env>`. The
  workflow targets specific labels per environment (`k3s-dev` vs
  `k3s-prod`), so dev pushes land on the dev cluster and main pushes
  land on prod without environment cross-contamination.
- Stale runner cleanup: every new instance (after a Spot reclaim) calls
  the GitHub API on first boot to delete every offline runner whose name
  starts with `k3s-runner-`, then registers itself. See ADR-009 §3 for
  the implementation.

The PAT used for runner registration is consumed **once** during boot
and immediately scrubbed from `/var/log/userdata.log` via `sed`. It is
not stored on disk after that point. The runner's outbound long-poll
authentication uses a per-runner registration token, not the PAT.

## Consequences

Pros

- **No inbound ports on the EC2**: the runner makes outbound long-poll
  calls to `pipelines.actions.githubusercontent.com`. The SG keeps 80
  and 443 open (for the app via traefik) and **nothing else** — SSH and
  the SSM-only path of `aws:ssm` can both be dropped.
- **No AWS credentials in the `deploy` job**: `kubectl` reads the local
  kubeconfig, containerd reads its local credentials helper. The deploy
  jobs in `.github/workflows/ci-cd.yml` have `permissions: contents:
  read` — no `id-token: write`, no `AWS_ROLE_ARN`. The OIDC role is
  only consumed by `build-push` and `image-scan` (which actually need
  ECR), which is principle-of-least-privilege.
- **No more SSM heredoc escaping**: deploy steps are plain shell, no
  quoting through SSM documents. Diff: `git log --grep='heredoc'
  --grep='SSM' --oneline | wc -l` collapsed from 8 fix commits to 0
  since the change.
- **Direct `kubectl rollout status`**: the pipeline blocks on the actual
  rollout — failure modes are immediate and the failing pod's `describe`
  output appears in the GitHub UI rather than buried in an SSM
  invocation log.
- **Per-environment isolation by label**: cleaner than per-environment
  SSM documents and trivial to inspect (`gh api /repos/.../actions/runners`).

Cons

- **~130 MB RAM on the node** (idle) + spikes to ~180 MB extra during a
  deploy (checkout + kustomize). On `t3.micro` this is the budget item
  that pushes the node closest to swap (see ADR-006's memory table).
- **The runner is a shared trust boundary with the cluster**. Anyone who
  can push to `develop` or `main` can run arbitrary code as the
  `ghrunner` user, which has cluster-admin on k3s. The trade-off is
  mitigated by GitHub Environment protection rules (only `production`
  runs on `main`, only `dev` runs on `develop`) and the OIDC role's
  trust policy scoping the `sub` claim to those environments, but in a
  real prod setup the runner should live on a separate instance.
- **The PAT must be valid at boot time**. If it expires while a Spot
  reclaim is in flight, the new instance will fail to register. Same
  failure mode and mitigation as documented in ADR-009 §"Trade-offs".
- **No ephemeral runner per job**: a persistent runner picks up
  consecutive jobs without re-pulling the runner binary, but it also
  means state from one job (e.g. checked-out repo at `_work/...`) can
  leak into the next. The `actions/checkout@v4` step clears the
  workspace by default so this is currently not an issue, but it is a
  contract to keep in mind.

## Alternatives revisited

- **SSM-based deploy** (the previous design) remains viable for setups
  where the deploy job genuinely should not share a trust boundary with
  the cluster. The reference implementation is preserved in git history
  (commits `110ac82` through `0d5c7c6`) — restore by re-introducing the
  `ssm:SendCommand` actions and dropping the `runs-on: [self-hosted, ...]`
  jobs.
- **GitHub-hosted runner with ephemeral k3s API exposure** (open
  apiserver on the SG, restrict by IP allowlist) was rejected: GitHub
  Actions egress IPs are large CIDR blocks that change weekly, so the
  allowlist would degenerate into "0.0.0.0/0" within a few rotations.
- **Argo CD / FluxCD pull-from-cluster** was rejected for scope: the
  brief asks for a CI/CD pipeline that deploys, not a GitOps controller
  running inside the cluster. A future iteration could swap the
  `deploy` jobs for a Flux `Kustomization` and turn the runner off
  entirely.

## Migration path

To move the runner off the EC2 (the natural next step once `t3.small`
or larger is in budget, or when the trust boundary becomes a real
concern):

1. Stand up a second `t3.micro` (or use ephemeral runners on
   `actions/runner-controller`) dedicated to running CI jobs.
2. Set `github_token = ""` on the `ec2-k3s` module — the `user-data`
   block conditioned on `github_token != ""` becomes a no-op and the
   k3s node no longer hosts a runner.
3. Recover `kubectl` access from the new runner by either:
   - exposing the k3s apiserver on a private link / Tailscale / VPN
     and reading a kubeconfig from a Secret on the new runner, or
   - shipping a small bastion-less deploy controller (Argo / Flux).
4. Update `runs-on:` in `.github/workflows/ci-cd.yml` to point at the
   new runner's labels.
5. Reclaim ~150 MB RAM on the k3s node — enough to lift the prod
   overlay back to 2 replicas (see ADR-006's "Migration path" §2).

## Decision review trigger

Revisit when any of the following become true:

- The runner's RAM footprint forces an OOM event on the k3s node
  (`kubectl -n demo-devops describe pod` shows reason `OOMKilled` and
  the `mem_used_percent` CloudWatch alarm is firing during deploys).
- The pipeline gains a job that should NOT have cluster-admin (e.g. a
  third-party security scan running attacker-supplied code in PRs from
  forks). At that point the deploy job's trust boundary must be moved
  off the cluster host.
- The cluster moves to multi-node — at that point a single colocated
  runner cannot reach every node's local kubeconfig and the model
  breaks down naturally.

## Cross-references

- ADR-001 — k3s on EC2 (why a single node)
- ADR-006 — Replica strategy and the t3.micro RAM budget that this
  runner consumes a slice of
- ADR-009 — Spot reclaim recovery, including the stale-runner cleanup
  logic that makes this design survive instance churn
- `terraform/modules/ec2-k3s/userdata.sh.tftpl` — runner installation
  and cleanup script
- `.github/workflows/ci-cd.yml` — `deploy-dev` / `deploy-prod` jobs
  with `runs-on: [self-hosted, k3s-<env>]`
