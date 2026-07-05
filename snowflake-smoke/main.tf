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

# ---- テスト実行ユーザー用のパスワード ---------------------------------------
# drt の Snowflake 接続はパスワード認証のみ対応(private_key 未対応)のため、
# キーペアと併用でパスワードも付与する。強度は Snowflake 既定ポリシー
# (8 文字以上・英大文字/小文字/数字を各 1 以上)を満たすよう生成。
# 記号は env ファイルやシェルでのクォート事故を避けるため使わない。
resource "random_password" "smoke" {
  length      = 20
  special     = false
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
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

  # メール通知:notify_triggers(%) 到達で「停止せず通知だけ」を送る。
  # 停止トリガー(90/100%)到達時も notify_users に通知される。
  # 通知が届くには各ユーザーが検証済みメール + 通知有効化済みであること。
  notify_triggers = var.monitor_notify_triggers
  notify_users    = var.monitor_notify_users
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

# ---- テスト実行ユーザー(キーペア認証 + パスワード併用)--------------------
resource "snowflake_user" "smoke" {
  name         = var.user_name
  comment      = "drt Snowflake smoke test"
  display_name = "drt Snowflake smoke test"

  # drt はパスワード認証のみ対応のため付与する。キーペアと併存でき、
  # 接続側が渡した資格情報に応じて Snowflake がどちらかで認証する。
  password = random_password.smoke.result

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

# ---- 実機確認用:読み取り専用ロール -----------------------------------------
# 人手での実機確認(テーブル参照)向け。SELECT のみで書き込み・DDL 不可。
# 書き込み用の smoke ロールとは分離し、確認者に余計な権限を渡さない。
resource "snowflake_account_role" "viewer" {
  name    = var.viewer_role_name
  comment = "drt smoke test read-only role for manual verification"
}

# SELECT 実行にはウェアハウスが要るので USAGE を付与(OPERATE は不要)。
# 対象は課金上限付きの smoke ウェアハウスなので暴走課金の心配はない。
resource "snowflake_grant_privileges_to_account_role" "viewer_warehouse" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.smoke.name
  }
}

# DB / スキーマの USAGE(オブジェクトを辿るのに必須)。
resource "snowflake_grant_privileges_to_account_role" "viewer_database" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.smoke.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_schema" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = snowflake_schema.smoke.fully_qualified_name
  }
}

# スキーマ内の表/ビューへ SELECT。既存(all)と将来(future)の両方に付与する。
# drt はテスト実行時に表を作るので、本命は future 側。
resource "snowflake_grant_privileges_to_account_role" "viewer_all_tables" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.smoke.fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_future_tables" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_schema          = snowflake_schema.smoke.fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_all_views" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "VIEWS"
      in_schema          = snowflake_schema.smoke.fully_qualified_name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "viewer_future_views" {
  account_role_name = snowflake_account_role.viewer.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "VIEWS"
      in_schema          = snowflake_schema.smoke.fully_qualified_name
    }
  }
}

# 読み取り専用ロールを実機確認するユーザーへ付与。
resource "snowflake_grant_account_role" "viewer" {
  for_each  = toset(var.viewer_user_names)
  role_name = snowflake_account_role.viewer.name
  user_name = each.value
}

# ---- ロール階層:カスタムロールを SYSADMIN 配下へぶら下げる ------------------
# Snowflake 推奨のロール階層に従い、カスタムロールを SYSADMIN に付与する。
# こうすると SYSADMIN(および ACCOUNTADMIN)がこれらのロールが所有する
# オブジェクトを管理できる。ACCOUNTADMIN 直下に孤立したカスタムロールを
# 作らないのがベストプラクティス。
resource "snowflake_grant_account_role" "smoke_to_sysadmin" {
  role_name        = snowflake_account_role.smoke.name
  parent_role_name = var.sysadmin_role_name
}

resource "snowflake_grant_account_role" "viewer_to_sysadmin" {
  role_name        = snowflake_account_role.viewer.name
  parent_role_name = var.sysadmin_role_name
}
