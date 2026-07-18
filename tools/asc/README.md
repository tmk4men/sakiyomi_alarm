# App Store Connect API で課金商品を作成

`asc_iap.py` は App Store Connect API を使って、さきよみアラームの課金商品を作成します。
App Store Connect の Web 画面でポチポチせず、コマンドで作れます（postura と同じ鍵を流用可）。

作成される商品:
- `sakiyomi_pro_monthly` … 月額サブスク ¥400
- `sakiyomi_pro_lifetime` … 買い切り（非消費型）¥900

## 前提

- 先に App Store Connect で **App 本体を登録**しておく（Bundle ID `app.sakiyomi.alarm`）。
- App Store Connect API キー（`.p8`）と Key ID / Issuer ID。postura のものをそのまま使えます。
- ロール: キーに **App Manager 以上**の権限が必要。

## 実行（Mac）

```bash
pip install 'pyjwt[crypto]'

export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=~/keys/AuthKey_XXXXXXXXXX.p8

# まず認証・アプリ確認（変更しない）
python3 tools/asc/asc_iap.py verify

# ストア文章＋課金商品をまとめて自動入力
python3 tools/asc/asc_iap.py all
```

### コマンド

| コマンド | 内容 |
|---|---|
| `verify` | 認証・アプリ検出・既存商品の一覧（変更なし） |
| `metadata` | アプリ名・サブタイトル・説明・キーワード・URL・プライバシーURL を自動入力 |
| `iap` | 月額¥400 サブスク・買い切り¥900 を作成 |
| `all` | metadata + iap をまとめて実行 |

ストア文章は `metadata.json` を編集して調整できます。

## API では自動化できない（手動が残る）

- **App 本体の新規登録**（最初の1回だけ Web で作成。Bundle ID `app.sakiyomi.alarm`）
- **バージョンの作成**（`metadata` はこの後に実行。無いとエラーで教えてくれます）
- **スクリーンショット**（画像の用意が必要）
- **年齢レーティング / App プライバシー(データ収集の申告)**
- **ビルドの紐付けと審査提出**（ビルドは `flutter build ipa` → アップロード）

## 注意

- Apple の課金APIは仕様変更が入りやすいです。`verify` で認証とアプリ検出を先に確認してください。
- 価格は Apple 固定の「価格ポイント」から選びます。¥400 / ¥900 の完全一致が無い場合は最も近い額を使い、警告を出します。
- サブスクは無料体験オファーを付けていません（仕様どおり）。
- 作成後、審査提出には別途スクショ・審査メモ等が必要です。

## postura のスクリプトに合わせたい場合

postura で動いている App Store Connect API スクリプトがあれば、その内容を共有してください。
同じ認証・エンドポイントの流儀に合わせて `asc_iap.py` を書き換えます（Apple API のバージョン差異を postura の実績に合わせられます）。
