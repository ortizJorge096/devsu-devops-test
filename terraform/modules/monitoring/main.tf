# ──────────────────────────────────────────────────────────────────────────
# Monitoring module — SNS topic + CloudWatch alarms.
#
# Alarms created:
#   - CPU utilization > N% (native EC2 metric)
#   - Status check failed (auto-recovery action)
#   - Memory utilization > N% (custom metric from CloudWatch Agent)
#   - Disk utilization > N% on the root volume (custom metric)
#
# Notifications go to the SNS topic; if an email is provided, a confirmable
# subscription is created. The recipient must click the confirmation link
# the first time.
#
# Free Tier note:
#   - SNS: first 1M publishes/month free.
#   - CloudWatch alarms: first 10 alarms free per account.
#   - CloudWatch custom metrics: first 10 metrics free per account.
# ──────────────────────────────────────────────────────────────────────────

# ─── SNS topic for alarm notifications ────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"

  tags = merge(var.tags, { Name = "${var.name}-alarms" })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# Allow CloudWatch to publish to the topic.
data "aws_iam_policy_document" "topic" {
  statement {
    sid     = "AllowCloudWatchPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    resources = [aws_sns_topic.alarms.arn]
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.topic.json
}

# ─── CPU utilization alarm ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "EC2 CPU > ${var.cpu_threshold_percent}% for ${var.evaluation_periods} periods of ${var.period_seconds}s"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  threshold           = var.cpu_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# ─── Status check failed alarm + EC2 auto-recovery ────────────────────────
# StatusCheckFailed is 0 (passing) or 1 (failing). If it averages > 0 for
# even one period, something is wrong. The recover action restarts the
# instance on healthy hardware automatically.
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.name}-status-check-failed"
  alarm_description   = "EC2 status check has been failing"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  # Auto-recover (moves the instance to healthy hardware).
  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover",
    aws_sns_topic.alarms.arn,
  ]

  tags = var.tags
}

data "aws_region" "current" {}

# ─── Memory + disk alarms (custom metrics from CloudWatch Agent) ──────────
resource "aws_cloudwatch_metric_alarm" "memory_high" {
  count               = var.enable_memory_disk_alarms ? 1 : 0
  alarm_name          = "${var.name}-memory-high"
  alarm_description   = "EC2 memory > ${var.memory_threshold_percent}%"
  namespace           = "DevsuDevops/EC2"
  metric_name         = "mem_used_percent"
  statistic           = "Average"
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  threshold           = var.memory_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  count               = var.enable_memory_disk_alarms ? 1 : 0
  alarm_name          = "${var.name}-disk-high"
  alarm_description   = "EC2 root filesystem > ${var.disk_threshold_percent}%"
  namespace           = "DevsuDevops/EC2"
  metric_name         = "disk_used_percent"
  statistic           = "Average"
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  threshold           = var.disk_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
