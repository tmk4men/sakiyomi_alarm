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
3. **Capability 追加（推奨）**
   - *+ Capability* → **Time Sensitive Notifications** を追加。集中モード中でもアラーム通知が届きやすくなります。
   - **Push Notifications は不要**（ローカル通知のみ）。
4. **表示名・アイコン**は設定済み（Info.plist の `CFBundleDisplayName`＝さきよみアラーム、`AppIcon` 生成済み）。

## 3. App Store Connect（ブラウザ）

1. **App を新規登録**：Bundle ID `app.sakiyomi.alarm`、名前「さきよみアラーム」。
2. **App内課金 / サブスク**を作成：
   - サブスク `sakiyomi_pro_monthly` … **月額 ¥400**（無料体験オファーは付けない）。
   - 非消費型 `sakiyomi_pro_lifetime` … **¥900**（買い切り）。
3. **App プライバシー**：トラッキングなし・データ収集なし（本アプリは端末内保存のみ）。
4. **URL 登録**：
   - 利用規約: `https://tmk4men.github.io/sakiyomi_alarm/terms.html`
   - プライバシー: `https://tmk4men.github.io/sakiyomi_alarm/privacy.html`
5. スクリーンショット等の掲載素材を用意。

> テストは **StoreKit Configuration** または **Sandbox** で。価格はストアから取得して表示されます（アプリ内の¥400/¥900はフォールバック表示）。

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
