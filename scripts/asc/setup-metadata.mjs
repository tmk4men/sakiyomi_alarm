#!/usr/bin/env node
// App Store の掲載文（説明・キーワード・サブタイトル・審査メモ等）を流し込む。アプリ非依存。
// 既定はドライラン。実行は --yes。冪等（何度実行しても最新の COPY で上書き）。
//
// 掲載文・URL・カテゴリ・appId は「アプリ固有設定ファイル asc.config.json」に書く。
// このスクリプト本体は編集不要（全アプリで使い回す）。
//
//   node <path>/setup-metadata.mjs ./asc.config.json          # 下見
//   node <path>/setup-metadata.mjs ./asc.config.json --yes    # 反映
//   # 実行フォルダに asc.config.json を置けばパス省略も可。

import path from "node:path";
import { fileURLToPath } from "node:url";
import { api, loadAppConfig } from "./lib.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const EXECUTE = argv.includes("--yes");

const APP = loadAppConfig(argv, HERE);
const LOCALE = APP.locale;
const COPY = APP.copy;
if (!COPY) {
  console.error("設定に copy がありません（asc.config.json の copy を確認）。");
  process.exit(1);
}
const appId = APP.appId;
const { PRIVACY_URL, SUPPORT_URL } = APP.urls;
// supportUrl / marketingUrl は個別指定が無ければ support ページに寄せる。
const SUPPORT = COPY.supportUrl || SUPPORT_URL;
const MARKETING = COPY.marketingUrl || SUPPORT_URL;
const CONTACT_EMAIL = APP.urls.CONTACT_EMAIL;

async function patch(label, endpoint, type, id, attributes) {
  if (!EXECUTE) {
    console.log(`  ＋更新予定: ${label}`);
    return;
  }
  await api("PATCH", endpoint, { data: { type, id, attributes } });
  console.log(`  ✅ 更新: ${label}`);
}

async function main() {
  console.log(`設定: ${APP.path}`);
  console.log(`アプリ ${appId} の掲載文 ${EXECUTE ? "【反映】" : "【ドライラン：変更しません】"}\n`);

  const EDITABLE = new Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY"]);

  // 1) バージョンの説明文・キーワード・宣伝文・新機能
  console.log("■ バージョン掲載文（説明・キーワード・宣伝文・新機能）");
  const vers = await api("GET", `/v1/apps/${appId}/appStoreVersions?limit=20`);
  const ver = (vers.data || []).find((v) => EDITABLE.has(v.attributes.appStoreState)) || vers.data?.[0];
  if (!ver) console.log("  ⚠ バージョンが見つかりません");
  else {
    const locs = await api("GET", `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations?limit=50`);
    const loc = (locs.data || []).find((l) => l.attributes.locale === LOCALE);
    if (!loc) console.log(`  ⚠ ${LOCALE} のローカライズがありません（画面で${LOCALE}を追加してから）`);
    else {
      await patch(`version localization ${LOCALE}`, `/v1/appStoreVersionLocalizations/${loc.id}`, "appStoreVersionLocalizations", loc.id, {
        description: COPY.description,
        keywords: COPY.keywords,
        promotionalText: COPY.promotionalText,
        supportUrl: SUPPORT,
        marketingUrl: MARKETING,
      });
      // whatsNew は初回バージョン(1.0)では編集不可（アップデート時のみ）。失敗しても止めない。
      if (COPY.whatsNew) {
        try {
          await patch(`whatsNew ${LOCALE}`, `/v1/appStoreVersionLocalizations/${loc.id}`, "appStoreVersionLocalizations", loc.id, { whatsNew: COPY.whatsNew });
        } catch {
          console.log("  ⚠ 新機能(whatsNew)は初回リリースでは設定不可のためスキップ");
        }
      }
    }
  }

  // 2) アプリ情報のサブタイトル
  console.log("■ サブタイトル");
  const infos = await api("GET", `/v1/apps/${appId}/appInfos?limit=10`);
  const info = infos.data?.[0];
  if (!info) console.log("  ⚠ appInfo が見つかりません");
  else if (COPY.subtitle) {
    const ilocs = await api("GET", `/v1/appInfos/${info.id}/appInfoLocalizations?limit=50`);
    const iloc = (ilocs.data || []).find((l) => l.attributes.locale === LOCALE);
    if (!iloc) console.log(`  ⚠ ${LOCALE} のアプリ情報ローカライズがありません`);
    else {
      try {
        await patch(`appInfo localization ${LOCALE}`, `/v1/appInfoLocalizations/${iloc.id}`, "appInfoLocalizations", iloc.id, {
          subtitle: COPY.subtitle,
          privacyPolicyUrl: PRIVACY_URL || undefined,
        });
      } catch {
        // privacyPolicyUrl がこのAPIで弾かれる場合はサブタイトルのみ設定し、URLは画面で。
        console.log("  ⚠ privacyPolicyUrl込みが失敗 → subtitleのみ設定（プライバシーURLは画面で貼付）");
        await patch(`appInfo localization ${LOCALE} (subtitle)`, `/v1/appInfoLocalizations/${iloc.id}`, "appInfoLocalizations", iloc.id, { subtitle: COPY.subtitle });
      }
    }
  } else console.log("  － subtitle 未設定（スキップ）");

  // 3) カテゴリ
  console.log("■ カテゴリ");
  if (!info) console.log("  ⚠ appInfo が見つかりません");
  else if (!APP.category) console.log("  － category 未設定（スキップ）");
  else if (!EXECUTE) console.log(`  ＋設定予定: ${APP.category}`);
  else {
    try {
      await api("PATCH", `/v1/appInfos/${info.id}`, {
        data: {
          type: "appInfos",
          id: info.id,
          relationships: { primaryCategory: { data: { type: "appCategories", id: APP.category } } },
        },
      });
      console.log(`  ✅ カテゴリ: ${APP.category}`);
    } catch (e) {
      console.log("  ⚠ カテゴリ設定失敗（画面で設定）: " + (e.message || "").split("\n").slice(-1)[0]);
    }
  }

  // 4) 審査メモ（App Review Information の Notes）＋ ログイン不要フラグ
  console.log("■ 審査メモ（App Review Notes）");
  if (!ver) console.log("  ⚠ バージョンが見つかりません");
  else if (!COPY.reviewNotes) console.log("  － reviewNotes 未設定（スキップ）");
  else if (!EXECUTE) console.log("  ＋審査メモ設定予定（ログイン不要も明記）");
  else {
    try {
      const rd = await api("GET", `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`).catch(() => null);
      const detailId = rd && rd.data && rd.data.id;
      if (detailId) {
        await api("PATCH", `/v1/appStoreReviewDetails/${detailId}`, {
          data: { type: "appStoreReviewDetails", id: detailId, attributes: { notes: COPY.reviewNotes, demoAccountRequired: false } },
        });
        console.log("  ✅ 審査メモ更新");
      } else {
        await api("POST", `/v1/appStoreReviewDetails`, {
          data: {
            type: "appStoreReviewDetails",
            attributes: { notes: COPY.reviewNotes, demoAccountRequired: false, contactEmail: CONTACT_EMAIL || undefined },
            relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: ver.id } } },
          },
        });
        console.log("  ✅ 審査メモ作成");
      }
    } catch (e) {
      console.log("  ⚠ 審査メモ設定失敗（画面: App Review Information → Notes）: " + (e.message || "").split("\n").slice(-1)[0]);
      console.log("    連絡先の氏名/電話は画面で入力が必要な場合あり。");
    }
  }

  console.log(`\n${EXECUTE ? "完了。App Store Connect の画面で反映を確認してください。" : "ドライラン完了。問題なければ --yes で反映してください。"}`);
}

main().catch((e) => {
  console.error("\n[エラー] " + (e.message || e));
  console.error("※ 冪等なので、原因を直して再実行すればOKです。");
  process.exit(1);
});
