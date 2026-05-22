output "sns_topic_arn" {
  description = "ARN of the SNS topic that receives alarm notifications."
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic."
  value       = aws_sns_topic.alarms.name
}

output "alarm_names" {
  description = "List of CloudWatch alarm names created."
  value = concat(
    [
      aws_cloudwatch_metric_alarm.cpu_high.alarm_name,
      aws_cloudwatch_metric_alarm.status_check.alarm_name,
    ],
    aws_cloudwatch_metric_alarm.memory_high[*].alarm_name,
    aws_cloudwatch_metric_alarm.disk_high[*].alarm_name,
  )
}

output "email_subscription_confirmation_hint" {
  description = "If you supplied alarm_email, AWS sent a confirmation email — check inbox & click confirm."
  value       = var.alarm_email == "" ? "(no email subscription — alarms will publish but nobody is listening)" : "Confirm subscription email sent to ${var.alarm_email}"
}
