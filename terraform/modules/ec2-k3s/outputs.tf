output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "Elastic IP — point a DNS A record here for a stable public URL."
  value       = aws_eip.this.public_ip
}

output "public_dns" {
  description = "Default AWS DNS hostname (EC2)."
  value       = aws_instance.this.public_dns
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
  description = "Open a shell on the node without SSH (uses SSM Session Manager)."
  value       = "aws ssm start-session --target ${aws_instance.this.id}"
}
