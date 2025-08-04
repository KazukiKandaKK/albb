# ALB サブドメイン方式での管理画面公開

## アーキテクチャ概要

```
インターネット
    ↓
外部ALB (Route53 + ACM)
├── api.example.com → Appコンテナ → 内部ALB → サービスA, サービスB
├── admin-a.example.com → サービスA管理画面 (直接)
└── admin-b.example.com → サービスB管理画面 (直接)
```

## 基本構成

### 1. ドメイン設定
- `api.example.com` - メインAPIエンドポイント
- `admin-a.example.com` - サービスA管理画面
- `admin-b.example.com` - サービスB管理画面

### 2. ALB構成
- **外部ALB**: インターネット向け、TLS終端
- **内部ALB**: VPC内部、サービス間通信用

### 3. サービス構成
- **Appコンテナ**: API処理、内部ALBへのプロキシ
- **サービスA**: ビジネスロジック + 管理画面ポート
- **サービスB**: ビジネスロジック + 管理画面ポート

## メリット

### ✅ パスベース方式との比較
| 項目 | サブドメイン方式 | パスベース方式 |
|------|------------------|----------------|
| **アセット配信** | 問題なし | 書き換え必要 |
| **認証・セッション** | 独立して動作 | 調整が必要 |
| **SSL証明書** | ワイルドカード1枚 | 1枚 |
| **運用複雑度** | 低 | 高 |

### ✅ 技術的利点
- フロントエンドアプリケーションがそのまま動作
- 相対パス・絶対パスの問題が発生しない
- 各サービスの設定変更が不要
- Cookie・CORS設定が単純

## セキュリティ

### 認証オプション
1. **ALB + Cognito認証**
   ```
   admin-*.example.com → Cognito認証 → サービス管理画面
   ```

2. **WAF IP制限**
   ```
   特定IPからのみ admin-*.example.com へのアクセス許可
   ```

3. **VPN限定**
   ```
   管理画面は内部ALBのみ、VPN経由でアクセス
   ```

## 実装パターン

### パターン1: 完全分離（推奨）
```
外部ALB:
├── api.example.com → Appコンテナ
├── admin-a.example.com → サービスA:8080
└── admin-b.example.com → サービスB:8080
```

### パターン2: 内部ALB経由
```
外部ALB:
├── api.example.com → Appコンテナ → 内部ALB
├── admin-a.example.com → 内部ALB → サービスA:8080
└── admin-b.example.com → 内部ALB → サービスB:8080
```

## 注意事項

1. **DNS設定**: Route53でワイルドカード設定 `*.example.com`
2. **SSL証明書**: ACMでワイルドカード証明書取得
3. **セキュリティグループ**: 管理画面ポートは外部ALBからのみ許可
4. **ログ監視**: CloudWatchで管理画面アクセスログを監視

## Route53設定手順

### 1. ドメイン準備
```bash
# 既存ドメインがある場合
example.com → Route53ホストゾーン作成済み

# 新規ドメインの場合
Route53でドメイン購入 or 外部レジストラからネームサーバー変更
```

### 2. ワイルドカード証明書の事前準備
```bash
# ACMでワイルドカード証明書を取得
*.example.com (DNS認証推奨)
```

### 3. Route53 DNSレコード設定

#### 方式A: 個別Aレコード（推奨）
```
api.example.com      A    ALB-DNS-NAME (Alias)
admin-a.example.com  A    ALB-DNS-NAME (Alias)
admin-b.example.com  A    ALB-DNS-NAME (Alias)
```

**メリット:** 
- 特定サブドメインのみ有効
- セキュリティが高い
- ログで区別しやすい

#### 方式B: ワイルドカードレコード
```
*.example.com        A    ALB-DNS-NAME (Alias)
```

**メリット:** 
- 管理が簡単
- 新しいサブドメイン追加時の設定不要

**注意点:** 
- 予期しないサブドメインも解決される
- セキュリティ上の考慮が必要

### 4. Terraform実装例

```hcl
# Route53ホストゾーン
data "aws_route53_zone" "main" {
  name = "example.com"
}

# ALB DNSレコード（個別設定）
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "admin-a.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "admin_b" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "admin-b.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

# または、ワイルドカードレコード
resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "*.example.com"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}
```

### 5. DNS伝播確認

```bash
# DNS設定確認
dig api.example.com
dig admin-a.example.com
dig admin-b.example.com

# ALBのDNS名と一致することを確認
nslookup your-alb-name.ap-northeast-1.elb.amazonaws.com
```

## ALB + ACM設定

### 1. ACMワイルドカード証明書

```hcl
# ACM証明書（DNS認証）
resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.example.com"
  validation_method = "DNS"

  subject_alternative_names = [
    "example.com"  # ルートドメインも含める場合
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# DNS認証レコード（自動作成）
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
```

### 2. 外部ALB設定

```hcl
# 外部ALB
resource "aws_lb" "external" {
  name               = "external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false

  tags = {
    Name = "external-alb"
  }
}

# HTTPS リスナー
resource "aws_lb_listener" "external_https" {
  load_balancer_arn = aws_lb.external.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate_validation.wildcard.certificate_arn

  # デフォルトアクション（404）
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
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
}
```

### 3. ターゲットグループ設定

```hcl
# APIアプリ用ターゲットグループ
resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = 3000
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
    Name = "app-target-group"
  }
}

# サービスA管理画面用ターゲットグループ
resource "aws_lb_target_group" "service_a_admin" {
  name     = "service-a-admin-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "service-a-admin-target-group"
  }
}

# サービスB管理画面用ターゲットグループ
resource "aws_lb_target_group" "service_b_admin" {
  name     = "service-b-admin-tg"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = {
    Name = "service-b-admin-target-group"
  }
}
```

### 4. リスナールール設定

```hcl
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
      values = ["api.example.com"]
    }
  }
}

# サービスA管理画面用ルール
resource "aws_lb_listener_rule" "service_a_admin" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    host_header {
      values = ["admin-a.example.com"]
    }
  }
}

# サービスB管理画面用ルール
resource "aws_lb_listener_rule" "service_b_admin" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    host_header {
      values = ["admin-b.example.com"]
    }
  }
}
```

## セキュリティグループ設定

```hcl
# 外部ALB用セキュリティグループ
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

# ECSタスク用セキュリティグループ
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # 外部ALBからのアクセス
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.external_alb.id]
  }

  # 管理画面ポート
  ingress {
    from_port       = 8080
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.external_alb.id]
  }

  # 内部ALBからのアクセス（必要に応じて）
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.internal_alb.id]
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
```

## 認証オプション実装

### オプション1: ALB + Cognito認証（推奨）

```hcl
# Cognito User Pool
resource "aws_cognito_user_pool" "admin" {
  name = "admin-user-pool"

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

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "admin" {
  name         = "admin-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  callback_urls = [
    "https://admin-a.example.com/oauth2/idpresponse",
    "https://admin-b.example.com/oauth2/idpresponse"
  ]

  logout_urls = [
    "https://admin-a.example.com",
    "https://admin-b.example.com"
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true
  supported_identity_providers         = ["COGNITO"]

  generate_secret = true
}

# Cognito User Pool Domain
resource "aws_cognito_user_pool_domain" "admin" {
  domain       = "admin-auth-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.admin.id
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# 管理画面ルールにCognito認証を追加
resource "aws_lb_listener_rule" "service_a_admin_auth" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 200

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.admin.arn
      user_pool_client_id = aws_cognito_user_pool_client.admin.id
      user_pool_domain    = aws_cognito_user_pool_domain.admin.domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    host_header {
      values = ["admin-a.example.com"]
    }
  }
}

resource "aws_lb_listener_rule" "service_b_admin_auth" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 300

  action {
    type = "authenticate-cognito"
    authenticate_cognito {
      user_pool_arn       = aws_cognito_user_pool.admin.arn
      user_pool_client_id = aws_cognito_user_pool_client.admin.id
      user_pool_domain    = aws_cognito_user_pool_domain.admin.domain
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    host_header {
      values = ["admin-b.example.com"]
    }
  }
}
```

### オプション2: WAF IP制限

```hcl
# WAF Web ACL
resource "aws_wafv2_web_acl" "admin_access" {
  name  = "admin-access-control"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "AllowAdminIPs"
    priority = 1

    override_action {
      none {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.admin_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                 = "AllowAdminIPs"
      sampled_requests_enabled    = true
    }

    action {
      allow {}
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                 = "AdminAccessControl"
    sampled_requests_enabled    = true
  }
}

# 許可IP設定
resource "aws_wafv2_ip_set" "admin_ips" {
  name  = "admin-allowed-ips"
  scope = "REGIONAL"

  ip_address_version = "IPV4"
  addresses = [
    "203.0.113.0/32",  # オフィスIP
    "198.51.100.0/32"  # VPN IP
  ]
}

# ALBにWAFを関連付け
resource "aws_wafv2_web_acl_association" "admin" {
  resource_arn = aws_lb.external.arn
  web_acl_arn  = aws_wafv2_web_acl.admin_access.arn
}

# 管理画面ルール（WAF適用版）
resource "aws_lb_listener_rule" "service_a_admin_waf" {
  listener_arn = aws_lb_listener.external_https.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    host_header {
      values = ["admin-a.example.com"]
    }
  }
}
```

### オプション3: Basic認証 + IP制限

```hcl
# Basic認証用のLambda関数
resource "aws_lambda_function" "basic_auth" {
  filename         = "basic_auth.zip"
  function_name    = "alb-basic-auth"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"

  source_code_hash = data.archive_file.basic_auth_zip.output_base64sha256
}

data "archive_file" "basic_auth_zip" {
  type        = "zip"
  output_path = "basic_auth.zip"
  source {
    content  = <<EOF
import base64
import json

def handler(event, context):
    auth_header = event['headers'].get('authorization', '')
    
    if not auth_header.startswith('Basic '):
        return unauthorized_response()
    
    encoded_credentials = auth_header[6:]
    try:
        decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
        username, password = decoded_credentials.split(':', 1)
    except:
        return unauthorized_response()
    
    # 認証チェック（実際は環境変数やSecrets Managerから取得）
    if username == 'admin' and password == 'secure_password':
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'message': 'Authenticated'})
        }
    
    return unauthorized_response()

def unauthorized_response():
    return {
        'statusCode': 401,
        'headers': {
            'WWW-Authenticate': 'Basic realm="Admin Area"',
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'message': 'Unauthorized'})
    }
EOF
    filename = "index.py"
  }
}

# Lambda用IAMロール
resource "aws_iam_role" "lambda_role" {
  name = "basic-auth-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}
```

## CloudWatch監視設定

```hcl
# ALBアクセスログ
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "alb-access-logs-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::582318560864:root"  # ap-northeast-1のELBアカウント
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/*"
      }
    ]
  })
}

# ALBでアクセスログ有効化
resource "aws_lb" "external_with_logging" {
  name               = "external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.external_alb.id]
  subnets            = var.public_subnets

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "external-alb"
  }
}

# CloudWatch アラーム
resource "aws_cloudwatch_metric_alarm" "admin_access_rate" {
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
}
```

## 完了チェックリスト

- [ ] Route53でドメイン設定完了
- [ ] ACMワイルドカード証明書発行・検証完了
- [ ] 外部ALB + ターゲットグループ設定完了
- [ ] リスナールール設定完了
- [ ] セキュリティグループ設定完了
- [ ] 認証方式の選択・実装完了
- [ ] CloudWatch監視設定完了
- [ ] DNS伝播確認完了
- [ ] 実際のアクセステスト完了