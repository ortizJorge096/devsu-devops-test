# Runbook — Switch between Spot and on-demand without re-architecting

## When to use this runbook

- AWS has Spot capacity shortages across all configured pools and the
  CloudWatch alarm `<name>-asg-unhealthy` is firing.
- You're about to demo / present the cluster to a reviewer and want
  zero risk of a Spot reclaim mid-demo.
- You're moving the workload from "demo" to "production-ish" and want
  reclaim-free behavior at the cost of ~$5/mo extra.

This runbook is a procedure. The architectural rationale lives in
[ADR-009](../decisions/ADR-009-spot-recovery-with-asg.md).

## Variables that control the mix

Two variables of the `ec2-k3s` module compose the Mixed Instances Policy
of the ASG:

| Variable | What it controls |
|---|---|
| `on_demand_base_capacity` | Number of on-demand instances **always** running, regardless of `desired`. |
| `on_demand_percentage_above_base_capacity` | Of the capacity above the base, what % runs on-demand. 0 = pure Spot. 100 = pure on-demand. |

With `desired = 1` (the current shape), both knobs are equivalent in
effect. The difference only shows up if you ever raise `max_size` above 1.

## Configurations

| Mode | `on_demand_base_capacity` | `on_demand_percentage_above_base_capacity` | Cost outside Free Tier |
|---|---|---|---|
| **100% Spot** (default) | 0 | 0 | ~$2/mo on t3.micro |
| **100% on-demand** (emergency / demo) | 0 | 100 | ~$7/mo on t3.micro |
| **Always at least one on-demand** | 1 | 0 | ~$7/mo on t3.micro |
| **Spot with on-demand fallback** (only when `max_size > 1`) | 0 | 50 | mixed |

## Procedure

### 1. Edit the env tfvars

```bash
cd terraform/environments/<env>     # dev or prod
vim terraform.tfvars
```

Add (or modify) the line:

```hcl
on_demand_percentage_above_base_capacity = 100
```

### 2. Plan and confirm

```bash
terraform plan -out=tfplan
```

The expected diff is a single in-place update on
`aws_autoscaling_group.this.mixed_instances_policy[0].instances_distribution`:

```
~ on_demand_percentage_above_base_capacity = 0 -> 100
```

### 3. Apply

```bash
terraform apply tfplan
```

The ASG starts an `instance_refresh` automatically because the LT/tags
changed. With `desired = 1` this means ~5 min of rollover (single-node
cluster cannot keep a healthy replica during the refresh).

If the rollover is unacceptable right now, you can edit the ASG
directly via the AWS console and re-launch instances later — Terraform
will reconcile on the next `apply`.

### 4. Verify

```bash
# Confirm the new instance is on-demand
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=$(terraform output -raw asg_name)" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceLifecycle,State.Name]' \
  --output table

# InstanceLifecycle column:
#   "spot"  → still Spot
#   null    → on-demand
```

Once the new instance is `Ready` and `InService`, the cluster is on
on-demand and immune to Spot reclaims.

### 5. Revert when you don't need it anymore

```bash
# Same flow but set the values back to 0
on_demand_percentage_above_base_capacity = 0

terraform plan -out=tfplan
terraform apply tfplan
```

Saves ~$5/mo.

## Cross-references

- [ADR-009 — Spot recovery via ASG + persistent EIP](../decisions/ADR-009-spot-recovery-with-asg.md)
- [ADR-006 — Single replica on AWS prod](../decisions/ADR-006-single-replica-on-aws.md)
- `terraform/modules/ec2-k3s/variables.tf` — the variable definitions
- `terraform/modules/ec2-k3s/main.tf` — the `mixed_instances_policy` block
