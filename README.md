# terraform-snowflake

`drt-hub/drt` の **Snowflake スモークテスト**を CI で実走させるために必要な
Snowflake リソースを、**Terraform** で作るためのリポジトリです。
([terraform-gcp](https://github.com/yodakanohoshi/terraform-gcp) の BigQuery 版を
Snowflake に置き換えたものです。)

「Terraform を触ったことがない」状態からでも進められるよう、手順・各リソースの意味・
**費用と後片付け(destroy)**・トラブルシュートまで解説したドキュメントを用意しています。

## このリポジトリの使い方

実際の設定とコマンドは **[`snowflake-smoke/`](./snowflake-smoke/) の README** にすべてまとまっています。

➡️ **まずはここを読んでください: [`snowflake-smoke/README.md`](./snowflake-smoke/README.md)**

ざっくりした流れ:

1. `snowflake-smoke/` に入り、接続先(組織名・アカウント名・管理ユーザー)を設定する
2. `terraform init` → `terraform plan` → `terraform apply` でリソースを作る
3. 出力された値を `drt-hub/drt` の GitHub Actions Secrets に登録する
4. 使い終わったら `terraform destroy` で **確実に全消去**(費用を残さない)

## 費用について(重要)

この構成は「**放置しても課金が積み上がらず、destroy で確実にゼロへ戻せる**」ことを最優先に作っています。

- ウェアハウス(唯一の課金源)は最小の **XSMALL**・生成時停止・**60 秒で自動停止**。クエリ実行中しか課金されません。
- DB / スキーマは **transient(Fail-safe 無し・Time Travel 0 日)**。`destroy` 後にストレージ課金が残りません。
- このウェアハウス専用の **リソースモニター**で月間クレジット上限をハードキャップ(既定 5 クレジット)。
- すべて Terraform 管理下なので、`terraform destroy` で漏れなく削除できます。

詳細は [`snowflake-smoke/README.md`](./snowflake-smoke/README.md) の「費用と後片付け」を参照してください。

## ディレクトリ構成

```
.
├── README.md               ← いまここ(概要)
└── snowflake-smoke/        ← Terraform 一式 + 詳細な手順書
    ├── README.md           ← 初心者向けの詳しい手順・解説
    ├── versions.tf         ← Terraform / provider のバージョンと接続設定
    ├── variables.tf        ← 入力(組織名・アカウント名・リソース名など)
    ├── main.tf             ← 作成するリソース本体
    ├── outputs.tf          ← 出力(GitHub Secrets 用の値)
    └── terraform.tfvars.example  ← 変数の記入例
```
