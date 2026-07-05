# =============================================================================
# drt Snowflake スモークテスト用リソース一式。
#
# 費用の考え方(destroy で確実にゼロに戻せる構成):
#   - DB / スキーマは transient + data_retention 0 日。Fail-safe が無いため
#     DROP 後にストレージ課金が残らない(通常 DB の 7 日 Fail-safe を回避)。
#   - ウェアハウスは XSMALL・initially_suspended・auto_suspend 60 秒。
#     クエリ実行中しか課金されず、放置しても自動停止する。
#   - リソースモニターを「このウェアハウスだけ」に紐づけ、月間クレジット上限で
#     ハードキャップ。他のウェアハウスには影響しない。
#   - すべて Terraform 管理下。terraform destroy で全消去できる。
# =============================================================================

# ---- テスト実行ユーザー用のキーペア(GCP の SA キー JSON に相当)-----------
# 秘密鍵はローカル state 内にのみ生成され、outputs 経由で取り出す。
resource "tls_private_key" "smoke" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# ---- コスト上限:リソースモニター -------------------------------------------
resource "snowflake_resource_monitor" "smoke" {
  name         = var.resource_monitor_name
  credit_quota = var.monitor_credit_quota

  frequency       = "MONTHLY"
  start_timestamp = var.monitor_start_timestamp

  # クォータの 90% で新規クエリ受付を停止、100% で実行中クエリも即キャンセル。
  suspend_trigger           = 90
  suspend_immediate_trigger = 100
}

# ---- コンピュート:ウェアハウス ---------------------------------------------
resource "snowflake_warehouse" "smoke" {
  name           = var.warehouse_name
  warehouse_size = var.warehouse_size

  # 生成時は停止状態。クエリが来たら自動起動、無操作 60 秒で自動停止。
  initially_suspended = true
  auto_resume         = "true"
  auto_suspend        = var.auto_suspend_seconds

  # 暴走クエリを打ち切る保険。
  statement_timeout_in_seconds = var.statement_timeout_seconds

  # このウェアハウス専用のコスト上限を紐づける。
  resource_monitor = snowflake_resource_monitor.smoke.name
}

# ---- ストレージ:捨て DB / スキーマ(transient・retention 0)---------------
resource "snowflake_database" "smoke" {
  name                        = var.database_name
  is_transient                = true
  data_retention_time_in_days = 0
  comment                     = "drt smoke test (transient, safe to destroy)"
}

resource "snowflake_schema" "smoke" {
  name                        = var.schema_name
  database                    = snowflake_database.smoke.name
  is_transient                = true
  data_retention_time_in_days = 0
}

# ---- 権限:最小権限ロール ---------------------------------------------------
resource "snowflake_account_role" "smoke" {
  name    = var.role_name
  comment = "drt smoke test least-privilege role"
}

# ウェアハウスの使用・起動。
resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  account_role_name = snowflake_account_role.smoke.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.smoke.name
  }
}

# DB の USAGE。
resource "snowflake_grant_privileges_to_account_role" "database" {
  account_role_name = snowflake_account_role.smoke.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.smoke.name
  }
}

# スキーマの使用 + オブジェクト作成(作成した表はロールが所有 = 読み書き自由)。
resource "snowflake_grant_privileges_to_account_role" "schema" {
  account_role_name = snowflake_account_role.smoke.name
  privileges        = ["USAGE", "CREATE TABLE", "CREATE VIEW", "CREATE STAGE"]

  on_schema {
    schema_name = snowflake_schema.smoke.fully_qualified_name
  }
}

# ---- テスト実行ユーザー(キーペア認証・パスワード無し)----------------------
resource "snowflake_user" "smoke" {
  name         = var.user_name
  comment      = "drt Snowflake smoke test"
  display_name = "drt Snowflake smoke test"

  # tls で生成した公開鍵を PEM ヘッダ/改行を除いた 1 行で登録する。
  rsa_public_key = trimspace(replace(replace(replace(
    tls_private_key.smoke.public_key_pem,
  "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", ""))

  default_warehouse = snowflake_warehouse.smoke.name
  default_role      = snowflake_account_role.smoke.name
  default_namespace = "${snowflake_database.smoke.name}.${snowflake_schema.smoke.name}"
}

# ロールをユーザーに付与。
resource "snowflake_grant_account_role" "smoke" {
  role_name = snowflake_account_role.smoke.name
  user_name = snowflake_user.smoke.name
}
