# ──────────────────────────────────────────────────────────────────────────
# Outputs — with the ASG model, the concrete instance_id is dynamic and
# changes after every Spot reclaim. We look it up via a data source so
# consumers (monitoring, CI tag filters) keep working.
# ──────────────────────────────────────────────────────────────────────────

# Look up whichever instance is currently in the ASG. After a reclaim this
# returns the new instance — Terraform will refresh on the next plan/apply.
data "aws_instances" "current" {
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.this.name
  }

  instance_state_names = ["running", "pending"]

  depends_on = [aws_autoscaling_group.this]
}

output "asg_name" {
  description = "Name of the Auto Scaling Group that owns the node — use this dimension for CloudWatch alarms so they survive Spot reclaims."
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "Launch template ID. Bump `tags` / image to force the ASG to roll the instance via instance_refresh."
  value       = aws_launch_template.this.id
}

output "instance_id" {
  description = "ID of whichever instance is currently in the ASG. Empty string = no instance running yet (cold start). Note: this changes on every Spot reclaim; prefer `asg_name` for stable references."
  value       = try(data.aws_instances.current.ids[0], "")
}

output "public_ip" {
  description = "Elastic IP — stable across Spot reclaims. nip.io FQDN is derived from this."
  value       = aws_eip.this.public_ip
}

output "eip_allocation_id" {
  description = "Allocation ID of the persistent EIP — passed into user-data so a fresh instance can re-attach it on boot."
  value       = aws_eip.this.allocation_id
}

output "app_url" {
  description = "Quick test URL for the app via traefik (HTTP)."
  value       = "http://${aws_eip.this.public_ip}/api/users"
}

output "health_url" {
  description = "Health endpoint (HTTP)."
  value       = "http://${aws_eip.this.public_ip}/health"
}

output "letsencrypt_host" {
  description = "nip.io FQDN baked into the user-data for Let's Encrypt HTTP-01 challenges. Resolves to the Elastic IP via wildcard DNS — no domain ownership required."
  value       = local.effective_public_host
}

output "app_url_https" {
  description = "HTTPS URL on the prod overlay. Real Let's Encrypt cert when enable_letsencrypt = true; traefik self-signed otherwise."
  value       = "https://${local.effective_public_host}/api/users"
}

output "ssm_session_command" {
  description = "Open a shell on the current ASG instance without SSH (uses SSM Session Manager). The data source re-resolves on the next `terraform refresh` after a reclaim."
  value       = try("aws ssm start-session --target ${data.aws_instances.current.ids[0]}", "(no running instance yet)")
}
