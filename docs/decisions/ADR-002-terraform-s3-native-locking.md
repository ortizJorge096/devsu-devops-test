# ADR 002 — Terraform 1.10 native S3 state locking

## Status
Accepted — 2026-05-21

## Context
Historically, the Terraform `s3` backend required a separate DynamoDB
table for the state lock (the `dynamodb_table` argument). That meant
provisioning, paying for (free tier 25 GB always), and explaining an
extra resource just to keep a single lock object.

Terraform 1.10 (GA Nov 2024) introduced **native S3 state locking** via
`use_lockfile = true`. The backend stores a `.tflock` object next to
the state file in the same bucket, which serves as the mutex.

## Decision
Set `required_version = ">= 1.10.0"` in every `versions.tf` and use:

```hcl
backend "s3" {
  bucket       = "<state-bucket>"
  key          = "<env>/terraform.tfstate"
  region       = "us-east-1"
  encrypt      = true
  use_lockfile = true     # native S3 locking — no DynamoDB needed
}
```

## Consequences

Pros
- One fewer resource to provision, one fewer thing for the reviewer
  to verify exists, one fewer IAM grant in the OIDC role.
- The lock survives if DynamoDB has a regional outage (S3 has a wider
  multi-AZ footprint).
- Easier to read for new joiners — the bucket *is* the lock.

Cons
- Locks the project to Terraform >= 1.10. Older CI runners must
  upgrade.
- The lock object lives in the same bucket as the state; an IAM role
  with `s3:PutObject` on the state path can both write state and steal
  the lock. (Same risk profile as the old DynamoDB pattern when the
  role had write access to both.)

## Migration note (if downgrading)
Set `use_lockfile = false` and add back:
```hcl
dynamodb_table = "<table>"
```
plus a `aws_dynamodb_table` resource in `bootstrap/main.tf` (LockID
hash key, BillingMode PAY_PER_REQUEST).
