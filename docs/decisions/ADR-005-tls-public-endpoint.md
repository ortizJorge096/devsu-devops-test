# ADR 005 — TLS for the public endpoint without a domain

## Status
Accepted — 2026-05-21

## Context
The brief asks for a publicly reachable endpoint. The endpoint we
provision is an Elastic IP attached to the EC2/k3s node (e.g.
`http://54.x.y.z/api/users`). It does **not** have a DNS name nor a
real TLS certificate by default. Browsers, integrations, and
security scanners increasingly expect HTTPS.

Three constraints make a "real" certificate non-trivial here:

1. We don't own a domain for this demo.
2. ACME certificate authorities (Let's Encrypt, ZeroSSL) issue
   certs only for domain names, not raw IPs.
3. AWS-managed ACM certs are free, but you can only use them with
   ALB / CloudFront / API Gateway — none of which fit Free Tier
   long-term (ALB ~$16/mo after the first 12 months).

## Decision

Layered approach, ordered by complexity:

### What is **shipped by default** (no extra config)
The Ingress is annotated to listen on **both 80 and 443**. k3s' built-in
traefik ingress controller terminates TLS with its own **self-signed
certificate** generated on first boot.

Result:
- `http://<EIP>/api/users` → 200 OK, plaintext.
- `https://<EIP>/api/users` → 200 OK after the browser accepts the
  warning ("Your connection is not private"). Acceptable for a demo.

This requires zero extra Terraform/K8s work — traefik does it
automatically.

### Upgrade path A — Bring your own domain (recommended for any non-demo use)
1. Register a domain (or use one you already own).
2. Create an A record pointing `<your-host>` → the Elastic IP.
3. Add **cert-manager** to k3s (Helm chart or static manifests).
4. Create a `ClusterIssuer` for Let's Encrypt (ACME HTTP-01).
5. Annotate the Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod`
   and add a `tls:` block referencing your host.
6. cert-manager auto-orders a real cert; traefik picks it up.

This produces a green-padlock cert with **zero cost** ($0 for DNS,
$0 for Let's Encrypt, $0 for cert-manager).

### Upgrade path B — No domain, use nip.io / sslip.io
[nip.io](https://nip.io) is a free DNS service that resolves any
`<ip>.nip.io` to `<ip>`. So `54-1-2-3.nip.io` resolves to `54.1.2.3`.

Combined with cert-manager + Let's Encrypt, this gives a **real
Let's Encrypt certificate** without owning a domain. Same steps as
path A, just point cert-manager at `<eip>.nip.io`.

Caveat: Let's Encrypt has rate limits per registered domain. nip.io
counts as a single eTLD+1, so heavy demo traffic across many users
sharing nip.io can hit limits.

### Upgrade path C — AWS ACM + ALB
- Provision an ALB with ACM cert (free), targets the EC2.
- ALB Free Tier covers the first 12 months (750 hrs/mo); after that,
  ~$16/mo.
- This is the standard pattern for ECS/EC2 in AWS production.

Recommended only if you migrate the deploy from k3s to ECS Fargate
or EKS+ALB Ingress controller.

## Consequences

Pros
- Demo works with HTTPS today, no extra cost, no extra services.
- Three clear upgrade paths documented for when "demo" becomes "real".

Cons
- Default cert is self-signed → browser warning. Automated clients
  must explicitly accept (`curl -k`, `--insecure`).
- No HSTS, no OCSP stapling, no certificate transparency log entries —
  none of which matter for an internal demo.

## Decision review trigger
Switch to upgrade path A (cert-manager + Let's Encrypt) as soon as a
domain is available — it takes ~30 minutes and removes the browser
warning entirely.
