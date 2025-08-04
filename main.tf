terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Route53ホストゾーン
data "aws_route53_zone" "main" {
  name = var.domain_name
}

# ランダム文字列生成
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# ===== ACM証明書 =====
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    var.domain_name
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "wildcard-cert"
  }
}

# DNS認証レコード
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# 証明書検証完了待ち
resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# ===== セキュリティグループ =====
resource "aws_security_group" "external_alb" {
  name        = "external-alb-sg"
  description = "Security group for external ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "external-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # 外部ALBからのアクセス（APIポート）
  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.external_alb.id]
  }

  # 管理画面ポート
  ingress {
    from_port       = var.service_a_admin_port
    to_port         = var.service_a_admin_port
    protocol        = "tcp"
    security_groups = [aws_security_group.external_alb.id]
  }

  ingress {
    from_port       = var.service_b_admin_port
    to_port         = var.service_b_admin_port
    protocol        = "tcp"
    security_groups = [aws_security_group.external_alb.id]
  }

  # 内部ALBからのアクセス（オプション）
  dynamic "ingress" {
    for_each = var.internal_alb_sg_id != null ? [1] : []
    content {
      from_port       = var.app_port
      to_port         = var.app_port
      protocol        = "tcp"
      security_groups = [var.internal_alb_sg_id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-tasks-sg"
  }
}

# ===== S3バケット（ALBログ用） =====
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "alb-access-logs-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Name = "alb-access-logs"
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.elb_account_id
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# ===== 外部ALB =====
resource "aws_lb" "external" {
  name               = var.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = var.enable_deletion_protection

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = var.enable_access_logs
  }

  tags = {
    Name = var.alb_name
  }
}

# HTTPS リスナー
resource "aws_lb_listener" "external_https" {
  load_balancer_arn = aws_lb.external.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = {
    Name = "external-https-listener"
  }
}

# HTTP → HTTPS リダイレクト
resource "aws_lb_listener" "external_http" {
  load_balancer_arn = aws_lb.external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name = "external-http-listener"
  }
}

# ===== ターゲットグループ =====
resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.app_health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "app-target-group"
  }
}

resource "aws_lb_target_group" "service_a_admin" {
  name     = "service-a-admin-tg"
  port     = var.service_a_admin_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.service_a_health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "service-a-admin-target-group"
  }
}

resource "aws_lb_target_group" "service_b_admin" {
  name     = "service-b-admin-tg"
  port     = var.service_b_admin_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.service_b_health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "service-b-admin-target-group"
  }
}

# ===== Route53 DNSレコード =====
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "admin-a.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin_b" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "admin-b.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

# ===== Cognito (オプション) =====
resource "aws_cognito_user_pool" "admin" {
  count = var.enable_cognito_auth ? 1 : 0
  name  = "admin-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  tags = {
    Name = "admin-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "admin" {
  count        = var.enable_cognito_auth ? 1 : 0
  name         = "admin-client"
  user_pool_id = aws_cognito_user_pool.admin[0].id

  callback_urls = [
    "https://admin-a.${var.domain_name}/oauth2/idpresponse",
    "https://admin-b.${var.domain_name}/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://admin-a.${var.domain_name}",
    "https://admin-b.${var.domain_name}"
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  generate_secret = true
}

resource "aws_cognito_user_pool_domain" "admin" {
  count        = var.enable_cognito_auth ? 1 : 0
  domain       = "admin-auth-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.admin[0].id
}

# ===== ALBリスナールール =====

# API用ルール
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    host_header {
      values = ["api.${var.domain_name}"]
    }
  }

  tags = {
    Name = "api-rule"
  }
}

# サービスA管理画面用ルール（Cognito認証あり）
resource "aws_lb_listener_rule" "service_a_admin_auth" {
  count        = var.enable_cognito_auth ? 1 : 0
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 200

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.admin[0].arn
      user_pool_client_id = aws_cognito_user_pool_client.admin[0].id
      user_pool_domain    = aws_cognito_user_pool_domain.admin[0].domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    host_header {
      values = ["admin-a.${var.domain_name}"]
    }
  }

  tags = {
    Name = "service-a-admin-auth-rule"
  }
}

# サービスA管理画面用ルール（認証なし）
resource "aws_lb_listener_rule" "service_a_admin" {
  count        = var.enable_cognito_auth ? 0 : 1
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    host_header {
      values = ["admin-a.${var.domain_name}"]
    }
  }

  tags = {
    Name = "service-a-admin-rule"
  }
}

# サービスB管理画面用ルール（Cognito認証あり）
resource "aws_lb_listener_rule" "service_b_admin_auth" {
  count        = var.enable_cognito_auth ? 1 : 0
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 300

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.admin[0].arn
      user_pool_client_id = aws_cognito_user_pool_client.admin[0].id
      user_pool_domain    = aws_cognito_user_pool_domain.admin[0].domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    host_header {
      values = ["admin-b.${var.domain_name}"]
    }
  }

  tags = {
    Name = "service-b-admin-auth-rule"
  }
}

# サービスB管理画面用ルール（認証なし）
resource "aws_lb_listener_rule" "service_b_admin" {
  count        = var.enable_cognito_auth ? 0 : 1
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    host_header {
      values = ["admin-b.${var.domain_name}"]
    }
  }

  tags = {
    Name = "service-b-admin-rule"
  }
}

# ===== CloudWatch アラーム =====
resource "aws_cloudwatch_metric_alarm" "admin_access_rate" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "admin-high-access-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "This metric monitors admin panel access rate"

  dimensions = {
    LoadBalancer = aws_lb.external.arn_suffix
  }

  tags = {
    Name = "admin-access-rate-alarm"
  }
}