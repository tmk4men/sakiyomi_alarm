#!/usr/bin/env node
// 課金商品を一括セットアップ（App Store Connect API）。アプリ非依存。
//   - 月額サブスク（自動更新）＋ 無料トライアル
//   - 買い切り（非消耗）
// すべて冪等（既にあれば作らずスキップ）。既定はドライラン。実行は --yes。
//
// 商品内容・価格・appId は「アプリ固有設定ファイル asc.config.json」に書く。
// このスクリプト本体は編集不要（全アプリで使い回す）。
//
// 使い方（Mac / どのプロジェクトからでも）:
//   node <path>/setup-iap.mjs ./asc.config.json          # 下見（作成しない）
//   node <path>/setup-iap.mjs ./asc.config.json --yes    # 実際に作成
//   # 設定ファイルを実行フォルダに asc.config.json という名前で置けばパス省略も可。
//   # appId だけ差し替えたいときは数字の引数で上書き: ... ./asc.config.json 1234567890

import path from "node:path";
import { fileURLToPath } from "node:url";
import { api, loadAppConfig } from "./lib.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const EXECUTE = argv.includes("--yes");

const APP = loadAppConfig(argv, HERE);
const PLAN = APP.plan;
if (!PLAN) {
  console.error("設定に plan がありません（asc.config.json の plan を確認）。");
  process.exit(1);
}
const appId = APP.appId;

// ドライランの表示付き作成。既存なら作らない。
async function ensure(label, findFn, createBody, createPath) {
  const existing = await findFn();
  if (existing) {
    console.log(`  ✓ 既存: ${label} (${existing.id})`);
    return existing;
  }
  if (!EXECUTE) {
    console.log(`  ＋作成予定: ${label}`);
    return { id: `(dry-run)`, dryRun: true };
  }
  const res = await api("POST", createPath, createBody);
  console.log(`  ✅ 作成: ${label} (${res.data.id})`);
  return res.data;
}

async function main() {
  console.log(`設定: ${APP.path}`);
  console.log(`アプリ ${appId} の課金セットアップ ${EXECUTE ? "【実行】" : "【ドライラン：作成しません】"}\n`);
  const warnings = [];

  // ===== 1. サブスクグループ =====
  console.log("■ サブスクグループ");
  const group = await ensure(
    `group "${PLAN.subscription.groupRef}"`,
    async () => {
      const r = await api("GET", `/v1/apps/${appId}/subscriptionGroups?limit=200`);
      return (r.data || []).find((g) => g.attributes.referenceName === PLAN.subscription.groupRef);
    },
    {
      data: {
        type: "subscriptionGroups",
        attributes: { referenceName: PLAN.subscription.groupRef },
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    },
    "/v1/subscriptionGroups",
  );

  // ===== 2. 月額サブスク =====
  console.log("■ 月額サブスク");
  let sub = null;
  if (!group.dryRun) {
    const r = await api("GET", `/v1/subscriptionGroups/${group.id}/subscriptions?limit=200`);
    sub = (r.data || []).find((s) => s.attributes.productId === PLAN.subscription.productId);
  }
  sub = await ensure(
    `subscription ${PLAN.subscription.productId}`,
    async () => sub,
    {
      data: {
        type: "subscriptions",
        attributes: {
          name: PLAN.subscription.name,
          productId: PLAN.subscription.productId,
          subscriptionPeriod: PLAN.subscription.period,
          groupLevel: 1,
        },
        relationships: { group: { data: { type: "subscriptionGroups", id: group.id } } },
      },
    },
    "/v1/subscriptions",
  );

  // ===== 3. サブスクのローカライズ =====
  if (!sub.dryRun) {
    console.log(`■ サブスク表示名（${PLAN.locale}）`);
    await ensure(
      `subscription localization ${PLAN.locale}`,
      async () => {
        const r = await api("GET", `/v1/subscriptions/${sub.id}/subscriptionLocalizations?limit=50`);
        return (r.data || []).find((l) => l.attributes.locale === PLAN.locale);
      },
      {
        data: {
          type: "subscriptionLocalizations",
          attributes: { name: PLAN.subscription.locName, locale: PLAN.locale, description: PLAN.subscription.locDesc },
          relationships: { subscription: { data: { type: "subscriptions", id: sub.id } } },
        },
      },
      "/v1/subscriptionLocalizations",
    );

    // ===== 4-5. 価格＆無料トライアル（失敗しても止めずに続行） =====
    try {
      console.log("■ サブスク価格");
      const pp = await api(
        "GET",
        `/v1/subscriptions/${sub.id}/pricePoints?filter[territory]=${PLAN.territory}&limit=200`,
      );
      const point = pickClosest(pp.data, PLAN.subscription.targetYen);
      if (!point) throw new Error("価格ポイントが取得できませんでした");
      console.log(`  対象価格ポイント: ¥${point.attributes.customerPrice} (${point.id})`);

      const hasPrice = (await api("GET", `/v1/subscriptions/${sub.id}/prices?limit=1`)).data?.length;
      if (hasPrice) console.log("  ✓ 既に価格設定あり");
      else if (!EXECUTE) console.log("  ＋価格設定予定");
      else {
        await api("POST", "/v1/subscriptionPrices", {
          data: {
            type: "subscriptionPrices",
            attributes: {},
            relationships: {
              subscription: { data: { type: "subscriptions", id: sub.id } },
              subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: point.id } },
            },
          },
        });
        console.log("  ✅ 価格設定");
      }

      // 無料トライアルは trialDuration が設定されているときだけ作成する。
      if (!PLAN.subscription.trialDuration) {
        console.log("■ 無料トライアル: なし（設定どおりスキップ）");
      } else {
        console.log("■ 無料トライアル");
        const offers = await api("GET", `/v1/subscriptions/${sub.id}/introductoryOffers?limit=10`);
        if (offers.data?.length) console.log("  ✓ 既にトライアルあり");
        else if (!EXECUTE) console.log(`  ＋${PLAN.subscription.trialDuration} 無料トライアル作成予定`);
        else {
          await api("POST", "/v1/subscriptionIntroductoryOffers", {
            data: {
              type: "subscriptionIntroductoryOffers",
              attributes: { duration: PLAN.subscription.trialDuration, offerMode: "FREE_TRIAL", numberOfPeriods: 1 },
              relationships: {
                subscription: { data: { type: "subscriptions", id: sub.id } },
              },
            },
          });
          console.log("  ✅ 無料トライアル作成");
        }
      }
    } catch (e) {
      warnings.push(`サブスクの価格/トライアル（App Store Connect の画面で¥${PLAN.subscription.targetYen}とトライアル${PLAN.subscription.trialDuration}を設定）`);
      console.log("  ⚠ 価格/トライアルで停止: " + (e.message || e).split("\n").slice(-1)[0]);
      console.log("    → 構造は出来ています。価格だけ後で画面設定でもOK（数十秒）。続行します…");
    }
  }

  // ===== 6. 買い切り（非消耗） =====
  console.log("■ 買い切り（非消耗）");
  const iap = await ensure(
    `IAP ${PLAN.lifetime.productId}`,
    async () => {
      const r = await api("GET", `/v1/apps/${appId}/inAppPurchasesV2?limit=200`);
      return (r.data || []).find((p) => p.attributes.productId === PLAN.lifetime.productId);
    },
    {
      data: {
        type: "inAppPurchases",
        attributes: { name: PLAN.lifetime.name, productId: PLAN.lifetime.productId, inAppPurchaseType: "NON_CONSUMABLE" },
        relationships: { app: { data: { type: "apps", id: appId } } },
      },
    },
    "/v2/inAppPurchases",
  );

  if (!iap.dryRun) {
    console.log(`■ 買い切り表示名（${PLAN.locale}）`);
    // GET の関係パスが弾かれるので、直接POSTして重複はエラーで判定する。
    try {
      await api("POST", "/v1/inAppPurchaseLocalizations", {
        data: {
          type: "inAppPurchaseLocalizations",
          attributes: { locale: PLAN.locale, name: PLAN.lifetime.locName, description: PLAN.lifetime.locDesc },
          relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap.id } } },
        },
      });
      console.log(`  ✅ 作成: IAP localization ${PLAN.locale}`);
    } catch (e) {
      const m = (e.message || "").toString();
      if (/already|duplicate|409/i.test(m)) console.log(`  ✓ 既存: IAP localization ${PLAN.locale}`);
      else {
        warnings.push("買い切りの表示名（画面で設定）");
        console.log("  ⚠ 表示名で停止: " + m.split("\n").slice(-1)[0]);
      }
    }
    // 買い切りの価格（価格スケジュール）
    try {
      console.log("■ 買い切り価格");
      const pp = await api(
        "GET",
        `/v2/inAppPurchases/${iap.id}/pricePoints?filter[territory]=${PLAN.territory}&limit=200`,
      );
      const point = pickClosest(pp.data, PLAN.lifetime.targetYen);
      if (!point) throw new Error("買い切りの価格ポイントが取得できません");
      console.log(`  対象価格ポイント: ¥${point.attributes.customerPrice}`);
      if (!EXECUTE) console.log("  ＋価格設定予定");
      else {
        await api("POST", "/v1/inAppPurchasePriceSchedules", {
          data: {
            type: "inAppPurchasePriceSchedules",
            relationships: {
              inAppPurchase: { data: { type: "inAppPurchases", id: iap.id } },
              manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${price}" }] },
              baseTerritory: { data: { type: "territories", id: PLAN.territory } },
            },
          },
          included: [
            {
              type: "inAppPurchasePrices",
              id: "${price}",
              attributes: { startDate: null },
              relationships: {
                inAppPurchasePricePoint: {
                  data: { type: "inAppPurchasePricePoints", id: point.id },
                },
              },
            },
          ],
        });
        console.log("  ✅ 買い切り価格設定");
      }
    } catch (e) {
      const m = (e.message || "").toString();
      if (/already|exist/i.test(m)) console.log("  ✓ 既に価格設定あり");
      else {
        warnings.push(`買い切りの価格（画面で¥${PLAN.lifetime.targetYen}を設定）`);
        console.log("  ⚠ 買い切り価格で停止: " + m.split("\n").slice(-1)[0]);
      }
    }
  }

  if (warnings.length) {
    console.log("\n― 画面で仕上げが必要な項目 ―");
    warnings.forEach((w) => console.log("  ・" + w));
  }
  console.log(`\n${EXECUTE ? "完了。" : "ドライラン完了。問題なければ --yes を付けて再実行してください。"}`);
}

function pickClosest(points, targetYen) {
  if (!points?.length) return null;
  return points
    .map((p) => ({ p, diff: Math.abs(Number(p.attributes.customerPrice) - targetYen) }))
    .sort((a, b) => a.diff - b.diff)[0].p;
}

main().catch((e) => {
  console.error("\n[エラー] " + (e.message || e));
  console.error("※ 冪等なので、原因を直して同じコマンドを再実行すれば続きから進みます。");
  process.exit(1);
});
