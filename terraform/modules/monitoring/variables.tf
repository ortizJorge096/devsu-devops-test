variable "name" {
  description = "Name prefix (e.g. devsu-devops)."
  type        = string
}

variable "alarm_email" {
  description = "Email that receives alarm notifications. Leave blank to skip the email subscription."
  type        = string
  default     = ""
}

# One of `asg_name` (preferred) or `instance_id` must be supplied.
variable "asg_name" {
  description = "Auto Scaling Group name to monitor. Preferred over instance_id because the dimension survives Spot reclaims."
  type        = string
  default     = ""
}

variable "instance_id" {
  description = "EC2 instance ID to monitor (legacy bare-EC2 deployments). Mutually exclusive with asg_name."
  type        = string
  default     = ""
}

variable "cpu_threshold_percent" {
  description = "CPU utilization above which the alarm fires (%)."
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "Memory utilization above which the alarm fires (%). Requires CloudWatch Agent on the node."
  type        = number
  default     = 85
}

variable "disk_threshold_percent" {
  description = "Disk utilization above which the alarm fires (%). Requires CloudWatch Agent."
  type        = number
  default     = 80
}

variable "evaluation_periods" {
  description = "Number of consecutive periods that must breach before the alarm fires."
  type        = number
  default     = 3
}

variable "period_seconds" {
  description = "Length of each evaluation period (seconds)."
  type        = number
  default     = 300
}

variable "enable_memory_disk_alarms" {
  description = "Whether to create the memory + disk alarms (require CloudWatch Agent on the node)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
