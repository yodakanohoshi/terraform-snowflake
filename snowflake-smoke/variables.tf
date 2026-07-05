# ---- 接続先(操作者の管理者アカウント)-------------------------------------

variable "organization_name" {
  type        = string
  description = "Snowflake の組織名(SHOW ORGANIZATION ACCOUNTS / アカウント識別子の前半)。"
}

variable "account_name" {
  type        = string
  description = "Snowflake のアカウント名(アカウント識別子の後半)。"
}

variable "admin_user" {
  type        = string
  description = "リソース作成に使う管理ユーザー名。ACCOUNTADMIN 相当の権限が必要。"
}

variable "admin_role" {
  type        = string
  description = "作成に使うロール。ウェアハウス/DB/リソースモニター/ユーザー作成のため ACCOUNTADMIN を推奨。"
  default     = "ACCOUNTADMIN"
}

# ---- 作成するリソース名 -----------------------------------------------------

variable "database_name" {
  type        = string
  description = "スモークテスト用の捨て DB 名。transient で作成され、destroy 時に即解放される。"
  default     = "DRT_SMOKE_DB"
}

variable "schema_name" {
  type        = string
  description = "スモークテスト用のスキーマ名。"
  default     = "DRT_SMOKE"
}

variable "warehouse_name" {
  type        = string
  description = "スモークテスト用のウェアハウス名。"
  default     = "DRT_SMOKE_WH"
}

variable "user_name" {
  type        = string
  description = "テスト実行用に作成するサービスユーザー名(キーペア認証)。"
  default     = "DRT_SMOKE_USER"
}

variable "role_name" {
  type        = string
  description = "サービスユーザーに付与する最小権限ロール名。"
  default     = "DRT_SMOKE_ROLE"
}

variable "viewer_role_name" {
  type        = string
  description = "実機確認用の読み取り専用ロール名。スキーマ内の表/ビューへの SELECT のみ持つ。"
  default     = "DRT_SMOKE_VIEWER_ROLE"
}

variable "viewer_user_names" {
  type        = list(string)
  description = "drt-smoke のテーブルを参照確認できる既存の Snowflake ユーザー名の一覧(実機確認する人)。ここに挙げたユーザーは Snowflake 上に既に存在している必要がある。tfvars で指定する。"
  default     = []
}

variable "sysadmin_role_name" {
  type        = string
  description = "カスタムロールをぶら下げる親ロール。Snowflake 推奨のロール階層に従い、既定は SYSADMIN。"
  default     = "SYSADMIN"
}

variable "resource_monitor_name" {
  type        = string
  description = "ウェアハウスにだけ紐づけるリソースモニター名(暴走課金の上限)。"
  default     = "DRT_SMOKE_MONITOR"
}

# ---- コスト関連(既定値で十分小さい)---------------------------------------

variable "warehouse_size" {
  type        = string
  description = "ウェアハウスサイズ。スモークテストは最小の XSMALL で十分。"
  default     = "XSMALL"
}

variable "auto_suspend_seconds" {
  type        = number
  description = "無操作でウェアハウスを自動停止するまでの秒数。課金の最小単位に合わせて 60 秒。"
  default     = 60
}

variable "statement_timeout_seconds" {
  type        = number
  description = "1 クエリの最大実行時間(秒)。暴走クエリの課金を止める保険。既定 1 時間。"
  default     = 3600
}

variable "monitor_credit_quota" {
  type        = number
  description = "リソースモニターの月間クレジット上限。到達で当該ウェアハウスを停止する。"
  default     = 5
}

variable "monitor_start_timestamp" {
  type        = string
  description = "リソースモニターの計測開始時刻。既定の IMMEDIATELY は「apply 時点」を意味し(MONTHLY で毎月リセット)、過去日時を弾くアカウントでも失敗しない。日時を固定したい場合は YYYY-MM-DD HH:MM 形式かつ未来を指定する。"
  default     = "IMMEDIATELY"
}

# ---- メール通知 -------------------------------------------------------------

variable "monitor_notify_users" {
  type        = list(string)
  description = "クレジット到達時にメール通知する Snowflake ユーザー名の一覧。各ユーザーは検証済みメールアドレスを持ち、通知を有効化している必要がある。空なら通知先なし。"
  default     = []
}

variable "monitor_notify_triggers" {
  type        = list(number)
  description = "『停止はせず通知だけ』を送るクレジット消費率(%)の一覧。例 [50, 80] で 50% と 80% で通知。停止トリガー(90/100%)到達時は常に通知される。"
  default     = [80]
}
