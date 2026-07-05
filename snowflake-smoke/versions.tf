terraform {
  required_version = ">= 1.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0, < 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

# Snowflake への接続情報。
# 認証情報(パスワード or 秘密鍵)は tfvars ではなく環境変数で渡す:
#   - パスワード方式:   export SNOWFLAKE_PASSWORD=...
#   - キーペア方式:     export SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
#                        export SNOWFLAKE_PRIVATE_KEY="$(cat admin_key.p8)"
# organization_name / account_name / user / role は変数から流し込む。
provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.admin_user
  role              = var.admin_role
}
