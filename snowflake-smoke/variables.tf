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
