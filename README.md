# さきよみアラーム (Sakiyomi Alarm)

**先の予定まで、まとめて設定できるアラーム。** 毎晩「明日は何時にしようかな」と迷わないために、1ヶ月分の起床時刻をカレンダーで一気に決められます。シフト勤務・不定休の人はもちろん、旅行や帰省など単発で早起きしたいときにも。

Flutter 製（iOS 本命 / Android も同一コードで対応可）。

---

## コンセプト

- **カレンダーが主役** — 月を一覧し、各日をタップして起床時刻を設定。
- **プリセットで塗る** — 「通常 7:00 / 早番 5:30 / 休み」などを登録し、カレンダーに塗るだけ。
- **個別編集** — 日をタップして「この日だけの時刻」に上書き、または休みに。
- **くり返し生成 (Pro)** — 「早番3・休1」等のパターンを期間まとめて流し込み。
- **課金** — 無料は今日から **7日先まで**設定可・プリセット3個まで。Pro で 7日より先・プリセット無制限・くり返し生成を解放。

## 画面

- **カレンダー** — 次のアラーム表示、月グリッド（8日目以降は無料だとフロスト＋Pro解放バンド）、月サマリー、下部にプリセットドック。
- **プリセット** — 一覧・追加・編集（名前 / 時刻 / 色 / 休みトグル）。
- **設定** — Pro、テーマ、既定スヌーズ、通知許可。

## 技術構成

- Flutter / Dart
- `flutter_local_notifications` + `timezone` + `flutter_timezone` … アラート（ローカル通知）
- `in_app_purchase` … サブスク課金（StoreKit / Google Play）
- `shared_preferences` … プリセット・日別設定・課金状態の永続化
- 状態管理は `ChangeNotifier`（`lib/data/app_store.dart`）＋ `ListenableBuilder`

```
lib/
  main.dart                 起動・初期化・MaterialApp
  constants.dart            課金プロダクトID・無料枠・色パレット
  models/                   Preset / DayPlan / ResolvedAlarm
  data/app_store.dart       状態＋永続化＋予定の解決ロジック
  services/                 notification / billing / globals
  theme/app_theme.dart      配色（ライト/ダーク）
  ui/                       calendar / presets / settings / paywall / rotation / day_sheet
```

## 開発・ビルド

前提: Flutter SDK（3.44 で確認）。iOS ビルドは **Mac + Xcode** が必要。

```bash
flutter pub get
flutter analyze          # 静的解析（No issues であること）
flutter test             # ユニットテスト
flutter run              # 実機/シミュレータで起動
```

### iOS 固有の設定（Xcode 側）

- **Bundle Identifier** を `app.sakiyomi.alarm` に設定（Runner ターゲット）。
- **表示名** は Info.plist の `CFBundleDisplayName`＝「さきよみアラーム」設定済み。
- **プライバシーマニフェスト**: `ios/Runner/PrivacyInfo.xcprivacy` を作成済み。Xcode で Runner ターゲットに追加（ドラッグ＆ドロップ、Target Membership を Runner に）してください。**申請に必須**。
- **Time Sensitive 通知**: Signing & Capabilities に *Time Sensitive Notifications* を追加すると、集中モード中も通知が届きやすくなります。
- **App Store Connect** で以下を作成。テストは Sandbox / StoreKit Configuration で。
  - `sakiyomi_pro_monthly` … 自動更新サブスク **月額 ¥400**（無料体験なし）
  - `sakiyomi_pro_lifetime` … 非消費型（買い切り）**¥900**
- アプリアイコン・スクリーンショットは別途用意。

### 法的文書（利用規約・プライバシーポリシー）

`docs/` に用意し、GitHub Pages で公開しています（アプリ内の課金画面からリンク）。

- 利用規約: <https://tmk4men.github.io/sakiyomi_alarm/terms.html>
- プライバシーポリシー: <https://tmk4men.github.io/sakiyomi_alarm/privacy.html>

**サービス終了時に有料機能が使えなくなる可能性**を利用規約 第4・5条で明記し、新規購入停止・自動更新停止・返金はストア規定に従う旨を規定しています。公開前に `[運営者名]`・所在地・施行日などのプレースホルダを確定し、必要に応じて専門家の確認を推奨します。

### iOS のアラームに関する制約（重要）

iOS はサードパーティに「確実に大音量で鳴り続ける全画面アラーム」を許しません。本アプリの起床通知は **ローカル通知** で実装しています。
- 通知音は短く、サイレント/集中モードで鳴らない場合があります（Time Sensitive で緩和）。
- 保留中のローカル通知は **64 件まで**。本アプリは通常アラーム最大 55 件＋スヌーズ枠として運用します（通常アラームは日付由来ID、スヌーズは専用IDレンジで分離）。

### 課金の既知の制約

`in_app_purchase` 単体ではサブスクの**有効期限切れ・返金・解約後の失効を検出できません**。付与済みの Pro はローカルに残り続けます。本番運用では **StoreKit2(JWS) またはサーバーでのレシート/署名検証**を追加し、期限・取消・猶予期間を同期してください（購入のキャンセル/エラーで解放しない安全策は実装済み）。

### Android（将来対応）

`android/app/src/main/AndroidManifest.xml` に通知・正確なアラームの権限と受信機を設定済み。`SCHEDULE_EXACT_ALARM` はランタイム許可が必要な場合があります。

## ステータス

- `flutter analyze`: No issues / `flutter test`: 通過。
- 課金・通知の実挙動は実機（iOS は Mac ビルド）での確認が必要。
- 効果音の同梱・ウィジェット・オンボーディングは今後の拡張余地。

---

Made with Flutter.
