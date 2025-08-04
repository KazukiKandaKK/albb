variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "domain_name" {
  description = "Domain name for the application (e.g., example.com)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "alb_name" {
  description = "Name for the external ALB"
  type        = string
  default     = "external-alb"
}

variable "app_port" {
  description = "Port for the main application"
  type        = number
  default     = 3000
}

variable "service_a_admin_port" {
  description = "Port for service A admin interface"
  type        = number
  default     = 8080
}

variable "service_b_admin_port" {
  description = "Port for service B admin interface"
  type        = number
  default     = 8081
}

variable "app_health_check_path" {
  description = "Health check path for the main application"
  type        = string
  default     = "/health"
}

variable "service_a_health_check_path" {
  description = "Health check path for service A admin interface"
  type        = string
  default     = "/"
}

variable "service_b_health_check_path" {
  description = "Health check path for service B admin interface"
  type        = string
  default     = "/"
}

variable "internal_alb_sg_id" {
  description = "Security group ID of internal ALB (optional)"
  type        = string
  default     = null
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "enable_access_logs" {
  description = "Enable ALB access logs"
  type        = bool
  default     = true
}

variable "enable_cognito_auth" {
  description = "Enable Cognito authentication for admin interfaces"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "elb_account_id" {
  description = "ELB service account ID for the region"
  type        = string
  default     = "582318560864"  # ap-northeast-1
  validation {
    condition = contains([
      "127311923021",  # us-east-1
      "033677994240",  # us-east-2
      "027434742980",  # us-west-1
      "797873946194",  # us-west-2
      "985666609251",  # ca-central-1
      "054676820928",  # eu-central-1
      "156460612806",  # eu-west-1
      "652711504416",  # eu-west-2
      "009996457667",  # eu-west-3
      "897822967062",  # eu-north-1
      "754344448648",  # eu-south-1
      "582318560864",  # ap-northeast-1
      "600734575887",  # ap-northeast-2
      "383597477331",  # ap-northeast-3
      "114774131450",  # ap-southeast-1
      "783225319266",  # ap-southeast-2
      "718504428378",  # ap-south-1
      "507241528517",  # sa-east-1
    ], var.elb_account_id)
    error_message = "Invalid ELB account ID for the region."
  }
}

# WAF設定用変数（オプション）
variable "enable_waf" {
  description = "Enable WAF for admin interfaces"
  type        = bool
  default     = false
}

variable "allowed_admin_ips" {
  description = "List of IP addresses allowed to access admin interfaces (CIDR format)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for ip in var.allowed_admin_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All IPs must be in valid CIDR format (e.g., 192.168.1.1/32)."
  }
}

# ECSタスク定義関連（オプション）
variable "app_task_definition_arn" {
  description = "ARN of the main app ECS task definition"
  type        = string
  default     = null
}

variable "service_a_task_definition_arn" {
  description = "ARN of service A ECS task definition"
  type        = string
  default     = null
}

variable "service_b_task_definition_arn" {
  description = "ARN of service B ECS task definition"
  type        = string
  default     = null
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = null
}

# タグ設定
variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "admin-portal"
    ManagedBy   = "terraform"
  }
}