# snowflake-smoke — Snowflake スモークテスト用リソース

`drt-hub/drt` の Snowflake スモークテストを CI で動かすために必要な最小リソースを
Terraform で作ります。作るものは次のとおりです。

| リソース | 目的 | 課金 |
| --- | --- | --- |
| ウェアハウス(XSMALL) | クエリ実行のコンピュート | **実行中のみ**。60 秒で自動停止 |
| リソースモニター | 上のウェアハウス専用のクレジット上限 | 無料(安全装置) |
| データベース / スキーマ(transient) | テストの読み書き先 | ストレージのみ。destroy で即解放 |
| ロール | 最小権限のまとめ | 無料 |
| ユーザー(キーペア認証) | テスト実行の接続主体 | 無料 |
| RSA キーペア | ユーザー認証(GCP の SA キー相当) | — |

---

## 0. 前提

- Terraform 1.5 以上(`terraform -version`)
- ACCOUNTADMIN 相当のロールで接続できる Snowflake ユーザー
  - ウェアハウス・リソースモニター・DB・ユーザー作成に必要
- アカウント識別子(組織名・アカウント名)。SnowSight 右下のアカウントメニュー、
  または SQL で確認できます:
  ```sql
  SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME();
  ```

## 1. 接続情報を設定する

`terraform.tfvars.example` をコピーして `terraform.tfvars` を作り、接続先を書きます。

```bash
cd snowflake-smoke
cp terraform.tfvars.example terraform.tfvars
```

```hcl
organization_name = "MYORG"
account_name      = "MYACCOUNT"
admin_user        = "MY_ADMIN_USER"
```

**認証情報(パスワード/秘密鍵)は tfvars に書かず、環境変数で渡します。**

- パスワード方式:
  ```bash
  export SNOWFLAKE_PASSWORD='...'
  ```
- キーペア方式(MFA 必須の環境などで推奨):
  ```bash
  export SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
  export SNOWFLAKE_PRIVATE_KEY="$(cat admin_key.p8)"
  ```

> Windows PowerShell の場合は `$env:SNOWFLAKE_PASSWORD='...'` のように設定します。

## 2. 作成する

```bash
terraform init
terraform plan      # 作成されるものを確認
terraform apply     # yes で実行
```

## 3. GitHub Secrets に登録する

`apply` 後、次の値を `drt-hub/drt` の **Settings → Secrets and variables → Actions** に登録します。

| Secret 名 | 取得コマンド |
| --- | --- |
| `SMOKE_SNOWFLAKE_ACCOUNT` | `terraform output -raw SMOKE_SNOWFLAKE_ACCOUNT` |
| `SMOKE_SNOWFLAKE_USER` | `terraform output -raw SMOKE_SNOWFLAKE_USER` |
| `SMOKE_SNOWFLAKE_PRIVATE_KEY` | `terraform output -raw SMOKE_SNOWFLAKE_PRIVATE_KEY` |
| `SMOKE_SNOWFLAKE_DATABASE` | `terraform output -raw SMOKE_SNOWFLAKE_DATABASE` |
| `SMOKE_SNOWFLAKE_SCHEMA` | `terraform output -raw SMOKE_SNOWFLAKE_SCHEMA` |
| `SMOKE_SNOWFLAKE_WAREHOUSE` | `terraform output -raw SMOKE_SNOWFLAKE_WAREHOUSE` |
| `SMOKE_SNOWFLAKE_ROLE` | `terraform output -raw SMOKE_SNOWFLAKE_ROLE` |

`SMOKE_SNOWFLAKE_PRIVATE_KEY` は PKCS#8 PEM(`-----BEGIN PRIVATE KEY-----` で始まる)の
全文です。改行込みでそのまま貼り付けてください。

## 4. 使い終わったら必ず destroy する

```bash
terraform destroy   # yes で全消去
```

これで作成した全リソースが消え、**追加の課金は残りません**(理由は下記)。

---

## 費用と後片付け(この構成の肝)

「費用が余計にかからず、確実に destroy できる」ように、次の設計にしています。

### 唯一の課金源=ウェアハウスを絞る
- サイズは最小の **XSMALL**(1 credit/hour 相当、秒課金・最低 60 秒)。
- `initially_suspended = true` で**停止状態で作成**。apply しただけでは課金されません。
- `auto_suspend = 60` で**無操作 60 秒で自動停止**。テストが落ちても放置課金になりません。
- `statement_timeout_in_seconds = 3600` で暴走クエリを打ち切り。

### ストレージを残さない
- DB・スキーマは **transient**。通常 DB にある **7 日間の Fail-safe が無い**ため、
  `DROP`(= destroy)した瞬間にストレージ課金が止まります。
- `data_retention_time_in_days = 0`(Time Travel 0 日)で、削除後に復元用データも残しません。

### ハードキャップ=リソースモニター
- **このウェアハウス専用**のリソースモニターを紐づけ、月間 `monitor_credit_quota`
  クレジット(既定 5)に達したら 90% で新規クエリ停止、100% で即キャンセルします。
- アカウント全体ではなく当該ウェアハウスだけを対象にするので、**他のウェアハウスには影響しません**。

### すべて Terraform 管理
- 手動で作った野良リソースが無いため、`terraform destroy` で漏れなく消えます。
- destroy 後に念のため確認する場合:
  ```sql
  SHOW WAREHOUSES  LIKE 'DRT_SMOKE_WH';
  SHOW DATABASES   LIKE 'DRT_SMOKE_DB';
  SHOW USERS       LIKE 'DRT_SMOKE_USER';
  SHOW ROLES       LIKE 'DRT_SMOKE_ROLE';
  SHOW RESOURCE MONITORS LIKE 'DRT_SMOKE_MONITOR';
  ```
  いずれも 0 件なら完全に片付いています。

---

## トラブルシュート

- **`Insufficient privileges to operate on ...`**
  `admin_role` が ACCOUNTADMIN でない可能性があります。ウェアハウス/リソースモニター/
  ユーザー作成には ACCOUNTADMIN が必要です。

- **`This session does not have a current database` などユーザー側の権限エラー**
  スモークユーザーには DB USAGE・スキーマ USAGE / CREATE TABLE 等を付与済みです。
  作成した表はユーザーのロールが所有するため、読み書き・DROP は自由に行えます。

- **キーペア認証が通らない**
  `SMOKE_SNOWFLAKE_PRIVATE_KEY` は PKCS#8(`BEGIN PRIVATE KEY`)である必要があります。
  本構成の出力はすでに PKCS#8 です。パスフレーズは付けていません。

- **リソースモニターが作れない / frequency エラー**
  `monitor_start_timestamp` は `YYYY-MM-DD HH:MM` 形式。過去日時で問題ありません。

---

## 作成されるリソース(参考)

| Terraform リソース | Snowflake オブジェクト |
| --- | --- |
| `tls_private_key.smoke` | ローカル生成の RSA キーペア(state 内) |
| `snowflake_resource_monitor.smoke` | リソースモニター |
| `snowflake_warehouse.smoke` | ウェアハウス |
| `snowflake_database.smoke` / `snowflake_schema.smoke` | DB / スキーマ(transient) |
| `snowflake_account_role.smoke` | ロール |
| `snowflake_user.smoke` | サービスユーザー(キーペア認証) |
| `snowflake_grant_privileges_to_account_role.*` | ウェアハウス/DB/スキーマへの権限付与 |
| `snowflake_grant_account_role.smoke` | ロール→ユーザーの付与 |
