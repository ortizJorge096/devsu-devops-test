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
  description = "Quick test URL for the app via traefik."
  value       = "http://${aws_eip.this.public_ip}/api/users"
}

output "health_url" {
  description = "Health endpoint."
  value       = "http://${aws_eip.this.public_ip}/health"
}

output "ssm_session_command" {
  description = "Open a shell on the node without SSH (uses SSM Session Manager)."
  value       = "aws ssm start-session --target ${aws_instance.this.id}"
}
