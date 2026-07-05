# drt-hub/drt の Actions シークレットに登録する値。
#
#   SMOKE_SNOWFLAKE_ACCOUNT      <- アカウント識別子(ORG-ACCOUNT 形式)
#   SMOKE_SNOWFLAKE_USER         <- 作成したサービスユーザー
#   SMOKE_SNOWFLAKE_PASSWORD     <- パスワード認証のパスワード(drt が使う)
#   SMOKE_SNOWFLAKE_PRIVATE_KEY  <- キーペア認証の秘密鍵(PKCS#8 PEM 全体)
#   SMOKE_SNOWFLAKE_DATABASE     <- 作成した DB
#   SMOKE_SNOWFLAKE_SCHEMA       <- 作成したスキーマ
#   SMOKE_SNOWFLAKE_WAREHOUSE    <- 作成したウェアハウス
#   SMOKE_SNOWFLAKE_ROLE         <- 付与したロール
#
# 秘匿値の取り出し:
#   terraform output -raw SMOKE_SNOWFLAKE_PASSWORD
#   terraform output -raw SMOKE_SNOWFLAKE_PRIVATE_KEY

output "SMOKE_SNOWFLAKE_ACCOUNT" {
  description = "接続用アカウント識別子(<組織名>-<アカウント名>)。"
  value       = "${var.organization_name}-${var.account_name}"
}

output "SMOKE_SNOWFLAKE_USER" {
  description = "テスト実行用に作成したサービスユーザー名。"
  value       = snowflake_user.smoke.name
}

output "SMOKE_SNOWFLAKE_PASSWORD" {
  description = "パスワード認証のパスワード。drt はパスワード方式のみ対応のため使う。"
  value       = random_password.smoke.result
  sensitive   = true
}

output "SMOKE_SNOWFLAKE_PRIVATE_KEY" {
  description = "キーペア認証の秘密鍵(PKCS#8 PEM)。GitHub Secret にそのまま登録する。"
  value       = tls_private_key.smoke.private_key_pem_pkcs8
  sensitive   = true
}

output "SMOKE_SNOWFLAKE_DATABASE" {
  description = "作成した捨て DB 名。"
  value       = snowflake_database.smoke.name
}

output "SMOKE_SNOWFLAKE_SCHEMA" {
  description = "作成したスキーマ名。"
  value       = snowflake_schema.smoke.name
}

output "SMOKE_SNOWFLAKE_WAREHOUSE" {
  description = "作成したウェアハウス名。"
  value       = snowflake_warehouse.smoke.name
}

output "SMOKE_SNOWFLAKE_ROLE" {
  description = "サービスユーザーに付与したロール名。"
  value       = snowflake_account_role.smoke.name
}
