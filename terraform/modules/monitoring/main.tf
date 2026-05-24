# ──────────────────────────────────────────────────────────────────────────
# Monitoring module — SNS topic + CloudWatch alarms.
#
# Supports two modes:
#   - asg_name (preferred): dimensions key on AutoScalingGroupName so the
#     alarms keep working after a Spot reclaim replaces the underlying
#     instance. The auto-recover action is NOT attached because the ASG
#     itself handles replacement on StatusCheckFailed_System.
#   - instance_id (legacy bare-EC2): dimensions key on InstanceId and the
#     status-check alarm attaches the ec2:recover action.
# ──────────────────────────────────────────────────────────────────────────

locals {
  use_asg = var.asg_name != ""
  use_iid = var.instance_id != ""

  ec2_dimensions = local.use_asg ? {
    AutoScalingGroupName = var.asg_name
    } : {
    InstanceId = var.instance_id
  }
}

resource "terraform_data" "validate_input" {
  lifecycle {
    precondition {
      condition     = local.use_asg != local.use_iid
      error_message = "monitoring module requires exactly one of `asg_name` or `instance_id` to be set."
    }
  }
}

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

data "aws_region" "current" {}

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

  dimensions = local.ec2_dimensions

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

# ─── Status check failed (legacy bare-EC2 only — auto-recover) ───────────
resource "aws_cloudwatch_metric_alarm" "status_check" {
  count = local.use_iid ? 1 : 0

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

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.current.name}:ec2:recover",
    aws_sns_topic.alarms.arn,
  ]

  tags = var.tags
}

# ─── ASG unhealthy alarm (preferred mode) ────────────────────────────────
# Pages the operator if the ASG ever runs with < 1 InService instance for
# 3 minutes — i.e. recovery itself is failing (e.g. no Spot capacity in
# any pool).
resource "aws_cloudwatch_metric_alarm" "asg_unhealthy" {
  count = local.use_asg ? 1 : 0

  alarm_name          = "${var.name}-asg-unhealthy"
  alarm_description   = "ASG has unhealthy or insufficient instances"
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

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

  dimensions = local.ec2_dimensions

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
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

  dimensions = local.ec2_dimensions

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}
