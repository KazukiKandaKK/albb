output "alb_dns_name" {
  description = "DNS name of the external ALB"
  value       = aws_lb.external.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the external ALB"
  value       = aws_lb.external.zone_id
}

output "alb_arn" {
  description = "ARN of the external ALB"
  value       = aws_lb.external.arn
}

output "certificate_arn" {
  description = "ARN of the wildcard SSL certificate"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

# ターゲットグループ
output "app_target_group_arn" {
  description = "ARN of the app target group"
  value       = aws_lb_target_group.app.arn
}

output "service_a_admin_target_group_arn" {
  description = "ARN of service A admin target group"
  value       = aws_lb_target_group.service_a_admin.arn
}

output "service_b_admin_target_group_arn" {
  description = "ARN of service B admin target group"
  value       = aws_lb_target_group.service_b_admin.arn
}

# セキュリティグループ
output "external_alb_security_group_id" {
  description = "Security group ID of the external ALB"
  value       = aws_security_group.external_alb.id
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  value       = aws_security_group.ecs_tasks.id
}

# Cognito（有効時のみ）
output "cognito_user_pool_id" {
  description = "ID of the Cognito user pool (if enabled)"
  value       = var.enable_cognito_auth ? aws_cognito_user_pool.admin[0].id : null
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito user pool (if enabled)"
  value       = var.enable_cognito_auth ? aws_cognito_user_pool.admin[0].arn : null
}

output "cognito_user_pool_client_id" {
  description = "Client ID of the Cognito user pool (if enabled)"
  value       = var.enable_cognito_auth ? aws_cognito_user_pool_client.admin[0].id : null
}

output "cognito_domain" {
  description = "Domain of the Cognito user pool (if enabled)"
  value       = var.enable_cognito_auth ? aws_cognito_user_pool_domain.admin[0].domain : null
}

# Route53レコード
output "api_fqdn" {
  description = "FQDN for API endpoint"
  value       = aws_route53_record.api.fqdn
}

output "admin_a_fqdn" {
  description = "FQDN for service A admin interface"
  value       = aws_route53_record.admin_a.fqdn
}

output "admin_b_fqdn" {
  description = "FQDN for service B admin interface"
  value       = aws_route53_record.admin_b.fqdn
}

# S3バケット
output "alb_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.bucket
}

output "alb_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs"
  value       = aws_s3_bucket.alb_logs.arn
}

# 接続情報
output "service_endpoints" {
  description = "Service endpoints for easy reference"
  value = {
    api     = "https://api.${var.domain_name}"
    admin_a = "https://admin-a.${var.domain_name}"
    admin_b = "https://admin-b.${var.domain_name}"
  }
}

# ECS接続用の情報
output "ecs_service_discovery" {
  description = "Information needed for ECS service configuration"
  value = {
    target_groups = {
      app         = aws_lb_target_group.app.arn
      service_a   = aws_lb_target_group.service_a_admin.arn
      service_b   = aws_lb_target_group.service_b_admin.arn
    }
    security_group = aws_security_group.ecs_tasks.id
    ports = {
      app       = var.app_port
      service_a = var.service_a_admin_port
      service_b = var.service_b_admin_port
    }
  }
}