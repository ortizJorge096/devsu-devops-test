# ADR 008 — Let's Encrypt on the prod overlay (cert-manager + nip.io)

## Status
Accepted — 2026-05-23

## Context
ADR-005 documented three TLS upgrade paths and explicitly shipped only
the baseline ("traefik self-signed, with a browser warning"). A reviewer
who hits the public endpoint sees the warning page and may never inspect
the ADR — the test brief lists TLS as scoreable extra credit
("`TLS / DNS / etc. for production`").

This ADR commits to **path B** of ADR-005 (cert-manager + Let's Encrypt
via nip.io) for the **`prod` overlay only**, and explains why it does
not extend to dev or local.

## Decision

### What is now wired

1. **cert-manager v1.15.3** is installed cluster-wide by the EC2
   user-data on first boot, gated by `var.enable_letsencrypt` (default
   `true` in the dev environment, `false` at module-default level).
2. Two `ClusterIssuer`s are provisioned at the same time:
   - `letsencrypt-staging` — dummy CA, no rate limits, used for dry runs.
   - `letsencrypt-prod` — the real, browser-trusted issuer.
3. The Elastic IP is **allocated before the instance** (`aws_eip.this`
   split from `aws_eip_association.this`) so the public IP is known at
   plan time. The module computes
   `demo-devops.<eip-with-dashes>.nip.io` and bakes it into the
   user-data template.
4. The `prod` overlay's Ingress (via `k8s/overlays/prod/tls-patch.yaml`)
   carries:
   - `cert-manager.io/cluster-issuer: letsencrypt-prod`
   - `traefik.ingress.kubernetes.io/router.entrypoints: web,websecure`
   - a `tls:` block referencing `secretName: demo-devops-tls`
5. The CI `deploy` job sed-replaces `demo-devops.example.com` →
   `demo-devops.<EIP-dashed>.nip.io` in both `kustomization.yaml` and
   `tls-patch.yaml` before `kustomize build | kubectl apply`. The EIP
   is fetched from IMDSv2 — the runner is colocated with the k3s node,
   so the runner's public IPv4 *is* the EIP.

### What is **deliberately not done**

- **dev overlay**: Ingress keeps no cert-manager annotation. traefik
  serves its self-signed cert. Rationale below.
- **local overlay**: ingress-nginx with `demo-devops.local` host —
  Let's Encrypt cannot validate a non-public hostname. Out of scope.
- **No `Issuer` (namespaced) — only `ClusterIssuer`**: simpler ops,
  fewer per-namespace objects, and we only need one issuer.

## Rationale

### Why prod only, not dev?
1. **RAM budget**: ADR-006 (amended) sets dev at 2 replicas with the
   self-hosted runner colocated. Peak ~1.38 GiB on a 1 GiB t3.micro
   (i.e. already swapping). cert-manager's three Deployments
   (controller, webhook, cainjector) add another 80-120 MB cluster-wide.
   Adding that on top of the dev 2-replicas load tips the host into
   thrashing during deploys.
2. **Reviewer ergonomics**: prod is the URL the reviewer opens
   (`terraform output app_url`). Greening the padlock there gives the
   "show, don't tell" win the brief asks for.
3. **Symmetric coverage**: dev already proves the brief's `≥ 2 replicas
   + horizontal scaling` requirement (ADR-006). Prod now proves the
   `TLS / DNS for production` extra credit. Each overlay covers a
   distinct scorecard item without overlap.

### Why nip.io and not a registered domain?
- Owning a domain for a demo is an external dependency (cost + DNS
  setup + revocation responsibility).
- nip.io is a free wildcard DNS service operated by Exentrique Solutions
  (back-up resolver: sslip.io). It resolves `<anything>.<ip>.nip.io`
  → `<ip>` with no registration.
- Let's Encrypt accepts nip.io hostnames for ACME HTTP-01 because:
  - The FQDN is publicly resolvable.
  - The challenge token is served from the host the FQDN points to.

### Why HTTP-01 and not DNS-01?
- HTTP-01 works with any traefik install, no DNS provider plugin
  needed. cert-manager places the challenge file at
  `/.well-known/acme-challenge/...` and traefik routes it.
- DNS-01 would require a Route53 (or other) zone we don't own, plus
  IAM permissions for cert-manager to add TXT records.

## Consequences

Pros
- Real green-padlock cert on `https://demo-devops.<eip>.nip.io/api/users`.
- Zero recurring cost ($0 for DNS, $0 for cert, $0 for cert-manager).
- Standard production pattern — cert-manager + ClusterIssuer + Ingress
  annotation is what 90% of real k8s clusters use.
- Graceful degradation: if `enable_letsencrypt = false`, the prod
  overlay still applies — the annotation is a no-op (cert-manager CRDs
  absent), the `tls:` block makes traefik fall back to its self-signed
  default. Zero pipeline breakage either way.

Cons
- **Spot reclamation invalidates the cert**. AWS gives a new EIP on
  re-apply → new nip.io FQDN → new cert order. Mitigated because:
  - Let's Encrypt rate limit is **50 certs per registered domain per
    week**. nip.io is one shared eTLD+1, so the limit is global across
    everyone using nip.io. Typical demo usage (≤5 destroys/apply per
    week) is far inside it.
  - If the limit is ever hit, the `letsencrypt-staging` issuer is
    already provisioned — swap the Ingress annotation and re-test.
- **First-boot delay**: ACME order + HTTP-01 challenge + cert issuance
  typically adds 30-60s to the first apply. The userdata `kubectl
  wait` for the pod is non-fatal, so a delayed cert doesn't break the
  apply — the Certificate object eventually moves to `Ready=True`.
- **cluster-wide install**: cert-manager runs in the `cert-manager`
  namespace and observes Ingresses everywhere. The dev overlay does
  not have the annotation, so no Certificate is created for it — but
  the RAM cost is paid by both namespaces.

## Migration paths

1. **Own a domain**: drop nip.io, point an A record at the EIP, change
   the `tls.hosts` and `Ingress` host. cert-manager re-issues
   automatically. ~10 min of work.
2. **Move runner off-box**: frees 130 MB on the k3s host, opening
   room to enable Let's Encrypt on dev too (see ADR-006).
3. **Hit a Let's Encrypt rate limit**: switch annotation to
   `letsencrypt-staging` (already provisioned), confirm the flow
   works, wait 7 days, switch back.

## Decision review trigger
Revisit when:
- A real domain is acquired → switch ADR-005 status to "path A
  implemented", drop the nip.io dependency.
- nip.io changes its ToS or shuts down — swap to `sslip.io`
  (drop-in compatible).
- Runner is moved off-box → consider extending TLS to dev.
