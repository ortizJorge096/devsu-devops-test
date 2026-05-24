# ADR-009 — Spot reclaim recovery via Auto Scaling Group + persistent EIP

- **Status:** Accepted
- **Date:** 2026-05-23
- **Supersedes:** part of ADR-001 (the lifecycle section)

## Context

The cluster runs on a single Spot EC2 instance to stay within (or just
above) AWS Free Tier (see ADR-001 + cost table in the README). Before this
ADR, the instance was provisioned as a bare `aws_instance` with
`instance_market_options.spot_instance_type = "one-time"`. That has two
known downsides:

1. **No auto-recovery.** When AWS reclaims the Spot instance (2-minute
   interruption notice), the instance is gone and stays gone. The cluster
   is down until somebody runs `terraform apply` again.
2. **Public IP churn.** Even though the EIP resource itself survives the
   reclaim, the `aws_eip_association` is bound to a specific
   `instance_id` that no longer exists, so the next apply tears it down
   and recreates it. In the worst case the EIP returns to the AWS pool
   and we get a new IP — which changes the `nip.io` FQDN and forces a
   fresh Let's Encrypt order (rate-limited to 50 certs/week per nip.io
   eTLD+1).

Both are unacceptable for a demo that's supposed to advertise a public
HTTPS endpoint to the reviewer.

## Decision

Replace the single `aws_instance` with an **Auto Scaling Group of size 1**
fed by a **Launch Template**, plus a **Mixed Instances Policy** spanning
several Spot pools. Keep the EIP as a separate, persistent resource and
re-attach it from `user-data` on every boot.

### Why ASG-of-1 instead of "Spot persistent" or Lambda+EventBridge

We weighed three options for recovery (these were presented to the
operator before the implementation):

| Approach | Pros | Cons |
|---|---|---|
| **ASG + Mixed Instances Policy** (chosen) | Native AWS replacement, multi-pool diversification, capacity rebalance, fits the same EIP pattern, no extra control-plane code | One indirection (Launch Template), slightly more Terraform |
| Spot persistent + EBS preservation | Keeps the same volume → SQLite survives | Doesn't help if AWS has no capacity at all; ties us to one instance type |
| Lambda + EventBridge on Spot interruption | Fine-grained control, can do graceful drain | Extra code surface, two more services to operate |

ASG wins because:

- AWS handles replacement end-to-end. No custom Lambdas or polling code.
- `mixed_instances_policy` lets us list 5 instance pools
  (`t3.micro / t3a.micro / t2.micro / t3.small / t3a.small`). The
  probability of a Spot drought across all five **in the same AZ** is
  much lower than for a single pool — and we still have the on-demand
  fallback toggle below.
- `capacity_rebalance = true` makes the ASG react to the Spot rebalance
  recommendation (~5 min ahead of the 2-min interruption notice on
  average), so we replace **before** the old instance dies — minimising
  the outage window.
- Same module exposes `on_demand_base_capacity` and
  `on_demand_percentage_above_base_capacity` for an emergency "go pure
  on-demand" switch without rewriting Terraform.

## Implementation

### 1. Module shape (`terraform/modules/ec2-k3s`)

```
aws_launch_template "this"          ← all the EC2 spec (AMI, user-data,
                                       IAM, ENI, EBS, IMDSv2)
aws_autoscaling_group "this"        ← desired_capacity = 1, min = 1,
                                       max = 1, mixed_instances_policy,
                                       capacity_rebalance, instance_refresh
aws_eip "this"                      ← unchanged: persistent allocation
aws_iam_role_policy "eip_associate" ← NEW: ec2:AssociateAddress scoped
                                       to this EIP's allocation_id only
```

`aws_instance` and `aws_eip_association` are gone — the ASG owns the
instance and the user-data owns the EIP attachment.

### 2. EIP re-association (in `user-data`)

At boot, before installing anything, the script runs:

```bash
IMDS_TOKEN=$(curl -X PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

# Retry — the previous owner may still be holding the EIP for a few seconds.
for attempt in 1..10; do
  aws ec2 associate-address \
       --region "$AWS_REGION" \
       --allocation-id "$EIP_ALLOC_ID" \
       --instance-id "$INSTANCE_ID" \
       --allow-reassociation \
    && break
  sleep 5
done
```

The IAM inline policy `<name>-eip-associate` allows
`ec2:AssociateAddress` only on this EIP's `AllocationId`, so a
compromised instance can't steal someone else's address.

### 3. Stale GitHub runner cleanup

When the ASG replaces an instance, the OLD self-hosted runner stays
registered as "offline" in the GitHub repo. Left unchecked, every reclaim
adds one zombie and eventually a `runs-on: self-hosted` job picks a
dead runner and times out. The new user-data calls the GitHub API to
delete every offline runner whose name starts with `k3s-runner-` before
registering itself:

```bash
curl -X DELETE \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/$OWNER/$REPO/actions/runners/$RUNNER_ID"
```

The `k3s-runner-` prefix scopes the deletion so other runners in the
repo aren't touched.

### 4. CloudWatch alarms now key on `AutoScalingGroupName`

The monitoring module gained an `asg_name` input that takes precedence
over `instance_id`. When `asg_name` is set:

- CPU / memory / disk alarms use the `AutoScalingGroupName` dimension
  (stable across reclaims).
- The EC2 auto-recover alarm is skipped — the ASG itself handles
  replacement on `StatusCheckFailed_System`.
- A new `<name>-asg-unhealthy` alarm fires when `GroupInServiceInstances
  < 1` for 3 minutes, so the operator gets paged if recovery itself
  fails (e.g. no Spot capacity across all five pools).

### 5. `instance_refresh` on Launch Template changes

The ASG has an `instance_refresh` block that rolls the instance whenever
the LT version or its tags change. `min_healthy_percentage = 0` because
desired = 1 — a single-node cluster can't keep a healthy replica during a
roll. For our demo this is acceptable (~5-7 min downtime on a rolling LT
change); for a real workload, raise `min_size` to 2 first.

## What survives a Spot reclaim, what does not

| Resource | Survives? | Notes |
|---|---|---|
| Elastic IP / nip.io FQDN | ✅ | EIP is decoupled, re-attached by user-data. |
| Let's Encrypt cert | ✅ | Same FQDN ⇒ no new order; cert lives in the cluster Secret which is *not* persisted, but cert-manager re-requests it from Let's Encrypt within the rate-limit window (it's the same hostname so the order succeeds). |
| ECR images | ✅ | Registry is regional, no link to the EC2. |
| Terraform state | ✅ | Lives in S3 (ADR-002). |
| App data in SQLite | ❌ | By design — `emptyDir` is per-pod and per-instance. See §"Data persistence" below. |
| k3s cluster identity | ❌ | New instance = new k3s install = new node ID. CI redeploys the workloads from manifests on first boot. |
| GitHub Actions runner | ❌ → ✅ | Old runner becomes offline; user-data deletes stale entries and registers fresh on new instance. |
| CloudWatch metric history | ⚠️ | `InstanceId`-keyed metrics from before the reclaim stay queryable but won't get new data. ASG-dimensioned alarms continue uninterrupted. |

## Data persistence

This ADR explicitly does **not** address persisting the application's
SQLite database across reclaims. The operator chose "accept loss" as the
SQLite strategy when this work was scoped, consistent with the demo
nature of the project. If durability becomes a requirement:

- **Easy:** move the data to a managed DB (RDS db.t3.micro is Free Tier
  eligible) and point the app at it via the existing Secret/ConfigMap.
- **Medium:** swap the `emptyDir` for an `aws-ebs-csi-driver` PVC. With
  desired = 1 instances and a stable AZ this gives durable storage at
  the cost of a tighter coupling between AZ and node.

Either path also resolves the parallel issue documented in
`docs/VALIDATION-REPORT.md` §3.2 (SQLite + 2 replicas = inconsistent
data per pod).

## Cost impact

Approximately zero. The ASG, Launch Template, and instance refresh API
calls are free. The instance count is unchanged (1 ⇢ 1). The Mixed
Instances Policy may pick `t3.small` over `t3.micro` on rare occasions
when micros are out of capacity — Spot price difference is ~$0.005/h.

## Trade-offs and limitations

1. **Outage window during reclaim ≈ 1-7 min**: 2 min interruption notice
   + 30-90 s for ASG to launch + 3-5 min for the user-data to bring k3s
   and the app back. Acceptable for a demo, not for a tier-1 service.
2. **First-boot from a cold image** every reclaim — no warm cache. Could
   be improved by baking a custom AMI with k3s + cert-manager
   pre-installed (Packer); deferred until needed.
3. **Single AZ** still applies (ADR-004). A whole-AZ outage takes the
   service down. Multi-AZ would require either two persistent instances
   (HA k3s with embedded etcd) or moving to EKS.
4. **GitHub PAT lifetime**: the cleanup logic and runner registration
   both consume the PAT on every boot. The PAT must be valid at boot
   time; if it expires while a reclaim is in flight, the new instance
   will not register as a runner and CI deploys will fail. Mitigation:
   PAT expiry alerts + a longer-lived PAT for the runner role.

## Migration

Rolling from the previous (bare `aws_instance`) state to this one is a
**destructive** operation on the running instance: Terraform plans a
delete of `aws_instance.this`, `aws_eip_association.this` and creates
the new ASG/LT. The EIP itself stays. Procedure:

```bash
cd terraform/environments/<env>
terraform plan -out=tfplan        # review carefully
terraform apply tfplan            # ~5 min replace
```

After the apply:
1. Confirm the new instance is `InService` in the ASG console.
2. Confirm the EIP is associated to the new instance.
3. `curl https://demo-devops.<eip>.nip.io/health` — should return 200.
4. Check the GitHub runner list — only one `k3s-runner-*` runner should
   be online.
