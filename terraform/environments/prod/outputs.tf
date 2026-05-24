output "ecr_repository_url" {
  description = "Push docker image here:  docker push <this>"
  value       = module.ecr.repository_url
}

output "github_actions_role_arn" {
  description = "Add this as the AWS_ROLE_ARN secret in GitHub Actions."
  value       = module.github_oidc.role_arn
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs across AZs."
  value       = module.network.public_subnet_ids
}

output "app_public_ip" {
  description = "Elastic IP of the k3s node — stable across Spot reclaims (ADR-009)."
  value       = var.enable_ec2_k3s ? module.k3s[0].public_ip : null
}

output "asg_name" {
  description = "Name of the Auto Scaling Group that owns the k3s node. A Spot reclaim replaces the instance here automatically."
  value       = var.enable_ec2_k3s ? module.k3s[0].asg_name : null
}

output "app_url" {
  description = "Public app URL via traefik on the k3s node (HTTP)."
  value       = var.enable_ec2_k3s ? module.k3s[0].app_url : null
}

output "app_url_https" {
  description = "Public app URL over HTTPS on the prod overlay."
  value       = var.enable_ec2_k3s ? module.k3s[0].app_url_https : null
}

output "letsencrypt_host" {
  description = "nip.io FQDN used as the Let's Encrypt SAN."
  value       = var.enable_ec2_k3s ? module.k3s[0].letsencrypt_host : null
}

output "health_url" {
  description = "Public health endpoint."
  value       = var.enable_ec2_k3s ? module.k3s[0].health_url : null
}

output "ssm_session_command" {
  description = "Open a shell on the k3s node via SSM Session Manager."
  value       = var.enable_ec2_k3s ? module.k3s[0].ssm_session_command : null
}

output "monitoring_sns_topic_arn" {
  description = "SNS topic that receives CloudWatch alarm notifications."
  value       = (var.enable_ec2_k3s && var.enable_monitoring) ? module.monitoring[0].sns_topic_arn : null
}

output "monitoring_alarms" {
  description = "Names of the CloudWatch alarms created."
  value       = (var.enable_ec2_k3s && var.enable_monitoring) ? module.monitoring[0].alarm_names : []
}
