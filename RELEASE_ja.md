# iOS リリース手順（Mac）

**Terminal・Xcode・App Store Connect の3つだけ**で完結します。アプリアイコンはリポジトリに同梱済みなので、clone すれば一緒に入ります（生成し直し不要）。

前提: Mac / Xcode インストール済み / Apple Developer Program 登録済み / Flutter SDK 導入済み。

---

## 1. 取得とビルド確認（Terminal）

```bash
git clone https://github.com/tmk4men/sakiyomi_alarm.git
cd sakiyomi_alarm
flutter pub get
flutter analyze          # No issues であること
open ios/Runner.xcworkspace   # Xcode が開く
```

## 2. Xcode 設定（GUIはここだけ・数分）

Runner ターゲットを選択して：

1. **Signing & Capabilities**
   - **Team**: 自分の Apple Developer チームを選択（Automatically manage signing にチェック）。
   - **Bundle Identifier**: `app.sakiyomi.alarm`（設定済み。必要なら確認のみ）。
2. **PrivacyInfo.xcprivacy をターゲットに追加**（審査に必須）
   - 左のファイルツリーで `Runner/PrivacyInfo.xcprivacy` を選択 → 右の *File Inspector* の **Target Membership** で **Runner** にチェック。
   - （ツリーに無ければ `ios/Runner/PrivacyInfo.xcprivacy` を Runner フォルダにドラッグ＆ドロップ。「Copy items if needed」不要、Target=Runner）。
3. **アラーム音をターゲットに追加**（iOSでカスタム音を鳴らすのに必須）
   - `ios/Runner/Sounds/` の `classic.caf` / `ring.caf` / `alarm.caf` を Runner フォルダにドラッグ＆ドロップ。
   - 「Copy items if needed」は不要、**Target=Runner** にチェック（＝Copy Bundle Resources に入る）。
   - これが無いと、選んだ音が鳴らず既定音になります。
4. **Capability 追加（推奨）**
   - *+ Capability* → **Time Sensitive Notifications** を追加。集中モード中でもアラーム通知が届きやすくなります。
   - **Push Notifications は不要**（ローカル通知のみ）。
5. **表示名・アイコン**は設定済み（Info.plist の `CFBundleDisplayName`＝さきよみアラーム、`AppIcon` 生成済み）。

## 3. App Store Connect

まず **App を新規登録**（ブラウザ）：Bundle ID `app.sakiyomi.alarm`、名前「さきよみアラーム」。バージョン(1.0)も作成。
（Appの新規登録だけは API 不可なので手動。ここまでできたら以降はコマンドで自動入力できます）

### 課金・掲載文を API で自動入力（posturaと同じ鍵）

`scripts/asc/` に App Store Connect API ツール一式が入っています（postura と同じもの）。
認証は共通の `~/.asc/config.json`（posturaのプロファイル）を流用。

```bash
# appId を確認（作成したアプリのID）
node scripts/asc/asc.mjs apps

# asc.config.sakiyomi.json の "appId" を上のIDに書き換える（または末尾に数字引数で上書き）

# 課金商品（月額¥400 / 買い切り¥900・トライアルなし）。まずドライラン→ --yes
node scripts/asc/setup-iap.mjs      scripts/asc/asc.config.sakiyomi.json
node scripts/asc/setup-iap.mjs      scripts/asc/asc.config.sakiyomi.json --yes

# 掲載文（説明・キーワード・サブタイトル・カテゴリ・審査メモ・URL）
node scripts/asc/setup-metadata.mjs scripts/asc/asc.config.sakiyomi.json
node scripts/asc/setup-metadata.mjs scripts/asc/asc.config.sakiyomi.json --yes
```

掲載文の内容は `scripts/asc/asc.config.sakiyomi.json` の `copy` を編集すれば変えられます。
`${TERMS_URL}`/`${PRIVACY_URL}` は自動展開されます（利用規約・プライバシーのURL）。

### 手動で残る（API不可）

- スクリーンショット、年齢レーティング、App プライバシー（データ収集の申告）、審査提出。
- テストは StoreKit Configuration / Sandbox。価格はストアから取得表示（アプリ内¥400/¥900はフォールバック）。

## 4. ビルドしてアップロード（Terminal）

```bash
flutter build ipa
```

`build/ios/ipa/*.ipa` が生成されます。アップロードは次のいずれか：

```bash
# A. Terminal から直接（App Store Connect API キー or Apple ID）
xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

または **Xcode Organizer**（Window > Organizer > Distribute App）／**Transporter** アプリでも可。

アップロード後、App Store Connect で審査提出。

---

## メモ

- **アイコン**は `assets/icon/icon.png` から `flutter_launcher_icons` で全サイズ生成済み・コミット済み。clone に含まれます。作り直す場合のみ `dart run flutter_launcher_icons`。
- **既知の制約**: サブスクの期限失効・返金の自動検出は未実装（本番前に StoreKit2/サーバー検証の追加を推奨）。詳細は `README.md`。
- **法的文書**の `[運営者名]`・所在地・施行日は公開前に確定してください（`docs/terms.html` / `docs/privacy.html`）。
