terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ===== Variables =====
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
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

variable "allowed_admin_ips" {
  description = "List of IP addresses allowed to access admin interfaces (CIDR format)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Warning: Open to all by default
}

variable "enable_separate_ports" {
  description = "Enable separate ports for admin interfaces instead of path-based routing"
  type        = bool
  default     = false
}

# ===== Security Groups =====
resource "aws_security_group" "alb" {
  name        = "simple-alb-sg"
  description = "Security group for simple HTTP ALB"
  vpc_id      = var.vpc_id

  # HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Admin ports (if enabled)
  dynamic "ingress" {
    for_each = var.enable_separate_ports ? [var.service_a_admin_port, var.service_b_admin_port] : []
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = var.allowed_admin_ips
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "simple-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "simple-ecs-tasks-sg"
  description = "Security group for ECS tasks (simple version)"
  vpc_id      = var.vpc_id

  # App port from ALB
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Admin ports from ALB
  ingress {
    from_port       = var.service_a_admin_port
    to_port         = var.service_a_admin_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = var.service_b_admin_port
    to_port         = var.service_b_admin_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "simple-ecs-tasks-sg"
  }
}

# ===== ALB =====
resource "aws_lb" "simple" {
  name               = "simple-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "simple-alb"
  }
}

# ===== Target Groups =====
resource "aws_lb_target_group" "app" {
  name     = "simple-app-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "simple-app-target-group"
  }
}

resource "aws_lb_target_group" "service_a_admin" {
  name     = "simple-service-a-admin-tg"
  port     = var.service_a_admin_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200,404"  # Allow 404 for path-based routing
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "simple-service-a-admin-target-group"
  }
}

resource "aws_lb_target_group" "service_b_admin" {
  name     = "simple-service-b-admin-tg"
  port     = var.service_b_admin_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200,404"  # Allow 404 for path-based routing
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "simple-service-b-admin-target-group"
  }
}

# ===== HTTP Listeners =====

# Main HTTP listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.simple.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = {
    Name = "simple-http-listener"
  }
}

# Separate port listeners (optional)
resource "aws_lb_listener" "admin_a_port" {
  count             = var.enable_separate_ports ? 1 : 0
  load_balancer_arn = aws_lb.simple.arn
  port              = var.service_a_admin_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  tags = {
    Name = "admin-a-port-listener"
  }
}

resource "aws_lb_listener" "admin_b_port" {
  count             = var.enable_separate_ports ? 1 : 0
  load_balancer_arn = aws_lb.simple.arn
  port              = var.service_b_admin_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  tags = {
    Name = "admin-b-port-listener"
  }
}

# ===== Listener Rules (Path-based routing) =====

# API routing rule
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  tags = {
    Name = "api-rule"
  }
}

# Service A admin routing rule (with IP restriction)
resource "aws_lb_listener_rule" "admin_a" {
  count        = var.enable_separate_ports ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-a/*", "/admin-a"]
    }
  }

  # IP restriction condition (if specific IPs are configured)
  dynamic "condition" {
    for_each = contains(var.allowed_admin_ips, "0.0.0.0/0") ? [] : [1]
    content {
      source_ip {
        values = var.allowed_admin_ips
      }
    }
  }

  tags = {
    Name = "admin-a-rule"
  }
}

# Service B admin routing rule (with IP restriction)
resource "aws_lb_listener_rule" "admin_b" {
  count        = var.enable_separate_ports ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-b/*", "/admin-b"]
    }
  }

  # IP restriction condition (if specific IPs are configured)
  dynamic "condition" {
    for_each = contains(var.allowed_admin_ips, "0.0.0.0/0") ? [] : [1]
    content {
      source_ip {
        values = var.allowed_admin_ips
      }
    }
  }

  tags = {
    Name = "admin-b-rule"
  }
}

# Static assets routing (for better path-based support)
resource "aws_lb_listener_rule" "admin_a_assets" {
  count        = var.enable_separate_ports ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 150

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-a/static/*", "/admin-a/css/*", "/admin-a/js/*", "/admin-a/assets/*"]
    }
  }

  tags = {
    Name = "admin-a-assets-rule"
  }
}

resource "aws_lb_listener_rule" "admin_b_assets" {
  count        = var.enable_separate_ports ? 0 : 1
  listener_arn = aws_lb_listener.http.arn
  priority     = 250

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-b/static/*", "/admin-b/css/*", "/admin-b/js/*", "/admin-b/assets/*"]
    }
  }

  tags = {
    Name = "admin-b-assets-rule"
  }
}

# ===== Outputs =====
output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.simple.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = aws_lb.simple.zone_id
}

output "target_group_arns" {
  description = "ARNs of all target groups"
  value = {
    app         = aws_lb_target_group.app.arn
    service_a   = aws_lb_target_group.service_a_admin.arn
    service_b   = aws_lb_target_group.service_b_admin.arn
  }
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb       = aws_security_group.alb.id
    ecs_tasks = aws_security_group.ecs_tasks.id
  }
}

output "access_urls" {
  description = "Access URLs for services"
  value = var.enable_separate_ports ? {
    api       = "http://${aws_lb.simple.dns_name}/api/"
    admin_a   = "http://${aws_lb.simple.dns_name}:${var.service_a_admin_port}/"
    admin_b   = "http://${aws_lb.simple.dns_name}:${var.service_b_admin_port}/"
  } : {
    api       = "http://${aws_lb.simple.dns_name}/api/"
    admin_a   = "http://${aws_lb.simple.dns_name}/admin-a/"
    admin_b   = "http://${aws_lb.simple.dns_name}/admin-b/"
  }
}