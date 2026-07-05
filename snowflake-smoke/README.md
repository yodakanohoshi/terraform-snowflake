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

## 0. Snowflake アカウントを作成する(まだ持っていない場合)

すでにアカウントがある場合はこの節を飛ばして「1. 前提」へ進んでください。

1. <https://signup.snowflake.com/> にアクセスし、氏名・メールアドレス等を入力します。
2. **エディション**を選びます。スモークテスト用途なら **Standard** で十分です。
3. **クラウドプロバイダとリージョン**を選びます(AWS / Azure / Google Cloud)。
   どれでも動きますが、CI や自分の環境から近いリージョンを選ぶと接続が速くなります。
   ※ プロバイダ・リージョンは後から変更できません。
4. 登録すると **30 日間・$400 分の無料トライアルクレジット**が付与されます。
   本構成はリソースモニター(既定 5 クレジット)で上限を絞っているため、
   トライアル枠内で余裕を持って収まります。
5. 確認メールが届くので **「CLICK TO ACTIVATE」** リンクを開き、
   初期ユーザーのユーザー名とパスワードを設定します。
   **この初期ユーザーには ACCOUNTADMIN ロールが付与されており**、そのまま本構成の
   `admin_user` として使えます。
6. Snowsight(Web UI)にログインできることを確認します。
   ログイン URL は `https://<アカウント識別子>.snowflakecomputing.com` 形式で、
   アクティベーションメールにも記載されています。
7. **アカウント識別子(組織名・アカウント名)を控えます。** 次のいずれかで確認できます。
   - Snowsight 左下のアカウントメニュー → アカウント名にホバー →
     **「Copy account identifier」**(`ORGNAME-ACCOUNTNAME` 形式でコピーされる。
     `-` の前が組織名、後がアカウント名)
   - SQL で確認:
     ```sql
     SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME();
     ```

> **MFA について**: Snowflake はパスワード認証の人間ユーザーに MFA 登録を求めます。
> 初回ログイン時に案内が出たら登録してください。MFA 有効時、Terraform からの接続は
> パスワード方式が通らない場合があるため、後述の**キーペア方式(`SNOWFLAKE_JWT`)を推奨**します。

## 1. 前提

- Terraform 1.5 以上(`terraform -version`)
- ACCOUNTADMIN 相当のロールで接続できる Snowflake ユーザー
  - ウェアハウス・リソースモニター・DB・ユーザー作成に必要
  - 上記 0 で作成した初期ユーザーがそのまま使えます
- アカウント識別子(組織名・アカウント名)。確認方法は上記 0-7 を参照。

## 2. 接続情報を設定する

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

> Windows PowerShell の場合はそれぞれ次のように設定します。
> ```powershell
> # パスワード方式
> $env:SNOWFLAKE_PASSWORD = '...'
>
> # キーペア方式(-Raw で改行込みの PEM 全体を 1 つの文字列として読み込む)
> $env:SNOWFLAKE_AUTHENTICATOR = 'SNOWFLAKE_JWT'
> $env:SNOWFLAKE_PRIVATE_KEY = Get-Content -Raw admin_key.p8
> ```
> `-Raw` を付けないと `Get-Content` が行の配列を返し、改行が半角スペースに潰れて
> PEM が壊れます。環境変数は同じ PowerShell ウィンドウ内でのみ有効なので、
> `terraform` も同じウィンドウで実行してください。

### キーペアの作成(キーペア方式を使う場合)

管理ユーザー(`admin_user`)用のキーペアを OpenSSL で作成し、公開鍵を Snowflake に登録します。
※ ここで作るのは **Terraform 実行者(管理ユーザー)用**のキーです。スモークテスト用
ユーザーのキーペアは Terraform が自動生成するため、手動で作る必要はありません。

1. 秘密鍵(PKCS#8・暗号化なし)と公開鍵を生成します:
   ```bash
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out admin_key.p8 -nocrypt
   openssl rsa -in admin_key.p8 -pubout -out admin_key.pub
   ```
   > Windows で `openssl` が無い場合は Git Bash に同梱されています
   > (`C:\Program Files\Git\usr\bin\openssl.exe`)。

2. 公開鍵を Snowflake に登録します。`admin_key.pub` の
   `-----BEGIN PUBLIC KEY-----` / `-----END PUBLIC KEY-----` 行を除いた本文を、
   Snowsight で自分のユーザーに設定します:
   ```sql
   ALTER USER MY_ADMIN_USER SET RSA_PUBLIC_KEY='MIIBIjANBgkqh...(admin_key.pub の本文)...';
   ```
   登録できたか確認:
   ```sql
   DESC USER MY_ADMIN_USER;
   -- RSA_PUBLIC_KEY_FP に SHA256:... が表示されれば OK
   ```

3. 秘密鍵 `admin_key.p8` は**リポジトリにコミットせず**、上記の環境変数
   `SNOWFLAKE_PRIVATE_KEY` で渡します。

## 3. 作成する

```bash
terraform init
terraform plan      # 作成されるものを確認
terraform apply     # yes で実行
```

## 4. GitHub Secrets に登録する

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

## 5. 使い終わったら必ず destroy する

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

### メール通知(任意)
クレジット消費が一定割合に達したらメールで知らせられます。tfvars で設定します。

```hcl
monitor_notify_users    = ["TAKUOTSUKA"]   # 通知を受け取る Snowflake ユーザー名
monitor_notify_triggers = [80]             # 何 % で「通知だけ」を送るか(複数可: [50, 80])
```

- `monitor_notify_triggers` は**停止を伴わない通知**のしきい値です。停止トリガー
  (90% 新規停止 / 100% 即キャンセル)に達したときも `monitor_notify_users` に通知されます。
- **通知が届くための前提**(これが無いとメールは飛びません):
  1. 対象ユーザーに**検証済みメールアドレス**が設定されていること。
     ```sql
     ALTER USER TAKUOTSUKA SET EMAIL = 'you@example.com';
     ```
     設定後、届く確認メールのリンクからメールアドレスを**検証**します
     (Snowsight: 右上のユーザー → Profile からも設定・確認可)。
  2. そのユーザーが**通知を有効化**していること
     (Snowsight: Profile → Notifications を ON)。
  3. 通知はアカウント管理者(ACCOUNTADMIN)ロールを持つユーザー向けの機能です。
     本構成の `admin_user` はこれに該当します。
- `monitor_notify_users` を空(既定)にすると通知先なしで、しきい値による停止だけが働きます。

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

- **リソースモニターが作れない(`090263 The specified Start time has already passed.`)**
  `monitor_start_timestamp` に過去の日時を指定すると、このエラーで失敗します。
  既定は `IMMEDIATELY`(apply 時点から計測開始)なので通常はそのままで問題ありません。
  日時を固定したい場合は `YYYY-MM-DD HH:MM` 形式で**未来**を指定してください。

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
