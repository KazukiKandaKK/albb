# ALB HTTP パスベース方式での管理画面公開（簡易版）

## アーキテクチャ概要

```
インターネット (HTTP:80のみ)
    ↓
外部ALB
├── /api/* → Appコンテナ → 内部ALB → サービスA, サービスB
├── /admin-a/* → サービスA管理画面 (直接)
└── /admin-b/* → サービスB管理画面 (直接)
```

## 特徴

### ✅ メリット
- **SSL証明書不要** - HTTP通信のみ
- **Route53不要** - ドメイン設定なし
- **最小構成** - ALBのみで実現
- **低コスト** - 追加料金なし

### ⚠️ 制約・注意点
- **セキュリティリスク** - 平文HTTP通信
- **パス書き換え問題** - アセット配信で404エラーの可能性
- **開発・テスト環境向け** - 本番環境非推奨

## パスベース方式の課題と対策

### 問題1: アセット参照エラー
```javascript
// 管理画面が生成するHTML
<script src="/static/js/app.js"></script>  // ❌ 404エラー
<link href="/css/style.css">               // ❌ 404エラー
```

### 対策1: サービス側設定変更
```bash
# 各サービスでベースパス設定
SERVICE_A_BASE_PATH=/admin-a
SERVICE_B_BASE_PATH=/admin-b
```

### 対策2: ALBでパス書き換え
```
/admin-a/static/* → サービスA:8080/static/*
/admin-a/api/* → サービスA:8080/api/*
/admin-a/* → サービスA:8080/*
```

## 実装パターン

### パターン1: サービス対応済み（推奨）
各サービスが `BASE_PATH` 環境変数に対応している場合

```bash
# 環境変数設定
SERVICE_A_BASE_PATH=/admin-a
SERVICE_B_BASE_PATH=/admin-b
```

### パターン2: ALB書き換え（制限あり）
サービス未対応の場合、ALBで可能な範囲で対応

```
# 静的アセット用ルール
/admin-a/static/* → target-group-a
/admin-a/css/* → target-group-a
/admin-a/js/* → target-group-a

# メインルール
/admin-a/* → target-group-a
```

### パターン3: 諦めて別ポート公開
```
http://alb-dns-name:8080 → サービスA管理画面
http://alb-dns-name:8081 → サービスB管理画面
```

## セキュリティ対策

### 1. セキュリティグループでIP制限
```hcl
resource "aws_security_group" "alb_restricted" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [
      "203.0.113.0/32",  # オフィスIP
      "10.0.0.0/8"       # VPC内部
    ]
  }
}
```

### 2. ALBリスナールールでIP制限
```hcl
resource "aws_lb_listener_rule" "admin_ip_restriction" {
  condition {
    source_ip {
      values = ["203.0.113.0/32", "198.51.100.0/32"]
    }
  }
  
  condition {
    path_pattern {
      values = ["/admin-*"]
    }
  }
}
```

## Terraform実装例

### 最小構成ALB
```hcl
resource "aws_lb" "simple" {
  name               = "simple-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnets
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.simple.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = "404"
      content_type = "text/plain"
      message_body = "Not Found"
    }
  }
}
```

### パスベースルーティング
```hcl
# APIルール
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
}

# 管理画面Aルール
resource "aws_lb_listener_rule" "admin_a" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-a/*"]
    }
  }
}

# 管理画面Bルール
resource "aws_lb_listener_rule" "admin_b" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-b/*"]
    }
  }
}
```

### IP制限付きルール
```hcl
resource "aws_lb_listener_rule" "admin_a_restricted" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }

  condition {
    path_pattern {
      values = ["/admin-a/*"]
    }
  }

  condition {
    source_ip {
      values = var.allowed_admin_ips
    }
  }
}
```

## 動作確認

```bash
# API確認
curl http://your-alb-dns-name/api/health

# 管理画面A確認
curl http://your-alb-dns-name/admin-a/

# 管理画面B確認
curl http://your-alb-dns-name/admin-b/
```

## 別ポート方式（代替案）

パスベースが困難な場合の代替案：

```hcl
# 追加リスナー（管理画面A用）
resource "aws_lb_listener" "admin_a_port" {
  load_balancer_arn = aws_lb.simple.arn
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_a_admin.arn
  }
}

# 追加リスナー（管理画面B用）
resource "aws_lb_listener" "admin_b_port" {
  load_balancer_arn = aws_lb.simple.arn
  port              = "8081"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_b_admin.arn
  }
}
```

**アクセス例:**
```
http://alb-dns-name:8080 → サービスA管理画面
http://alb-dns-name:8081 → サービスB管理画面
```

## 本番移行パス

開発・テスト環境で動作確認後：

1. **SSL証明書追加** → HTTPS化
2. **独自ドメイン設定** → Route53追加
3. **サブドメイン方式移行** → パス問題解消
4. **認証機能追加** → Cognito/WAF

## まとめ

**使い分け:**
- **開発・テスト**: HTTP + パスベース（この方式）
- **本番環境**: HTTPS + サブドメイン（メインREADME方式）

**成功の鍵:**
1. サービス側でBASE_PATH対応
2. 適切なIP制限設定
3. 段階的な本番移行計画