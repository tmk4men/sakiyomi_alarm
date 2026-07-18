#!/usr/bin/env node
// App Store Connect API 自動化CLI（外部依存なし・Node標準のみ）。
//
// 認証情報（3点）は環境変数 or scripts/asc/.asc.json から読む。秘密鍵(.p8)は端末内に置き、
// 絶対にコミットしない（.gitignore 済み）。
//   ASC_KEY_ID     … キーID
//   ASC_ISSUER_ID  … Issuer ID
//   ASC_KEY_PATH   … .p8 のパス
//
// 使い方:
//   node scripts/asc/asc.mjs token                 # JWT を出力（curl等のデバッグ用）
//   node scripts/asc/asc.mjs apps                  # 自分のアプリ一覧（id/名前/bundleId）
//   node scripts/asc/asc.mjs builds <appId>        # ビルド一覧
//   node scripts/asc/asc.mjs iaps <appId>          # App内課金（非消耗/消耗等）一覧
//   node scripts/asc/asc.mjs subgroups <appId>     # サブスクグループ一覧
//   node scripts/asc/asc.mjs subs <groupId>        # グループ内サブスク一覧
//   node scripts/asc/asc.mjs get <path> [k=v ...]  # 任意GET（例: get /v1/apps limit=5）
//   node scripts/asc/asc.mjs sales <vendorId>      # 前日の売上サマリーレポート(gz)を保存
//
// 参考: https://developer.apple.com/documentation/appstoreconnectapi

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BASE = "https://api.appstoreconnect.apple.com";

// 書き込みは既定でドライラン。--yes / --execute を付けたときだけ実際に送信する。
let EXECUTE = false;

// ---------- 認証（複数アプリ／複数アカウントで使い回せる設計） ----------
//
// APIキーは Apple アカウント（チーム）単位。同じチームの全アプリは1つの鍵で操作できる。
// 別チーム（別Apple ID）を使うときだけ profiles を分ける。
//
// 設定の探索順（先に見つかった有効なものを使用）:
//   1. 環境変数 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH（--profile 指定が無いとき）
//   2. ./.asc.json               （実行中のプロジェクト固有）
//   3. <このスクリプトと同じ場所>/.asc.json
//   4. ~/.asc/config.json        （全プロジェクト共通のグローバル設定）
//
// .asc.json / config.json はどちらの形でも可:
//   単一:    { "keyId": "...", "issuerId": "...", "keyPath": "AuthKey_XXX.p8" }
//   複数:    { "default": "postura",
//             "profiles": { "postura": {..}, "otherapp": {..} } }
//   keyPath は設定ファイルからの相対 or 絶対。

function configCandidates() {
  return [
    path.join(process.cwd(), ".asc.json"),
    path.join(HERE, ".asc.json"),
    path.join(os.homedir(), ".asc", "config.json"),
    path.join(os.homedir(), ".asc.json"),
  ];
}

function pickFromFile(obj, fileDir, profileName) {
  let creds;
  if (obj && obj.profiles) {
    const name = profileName || obj.default || Object.keys(obj.profiles)[0];
    creds = obj.profiles[name];
    if (!creds) return null;
  } else {
    creds = obj;
  }
  if (!creds || !creds.keyId || !creds.issuerId || !creds.keyPath) return null;
  const keyPath = path.isAbsolute(creds.keyPath)
    ? creds.keyPath
    : path.resolve(fileDir, creds.keyPath);
  return { keyId: creds.keyId, issuerId: creds.issuerId, keyPath };
}

function loadConfig(profileName) {
  // プロファイル未指定で環境変数が揃っていれば最優先。
  if (
    !profileName &&
    process.env.ASC_KEY_ID &&
    process.env.ASC_ISSUER_ID &&
    process.env.ASC_KEY_PATH
  ) {
    return {
      keyId: process.env.ASC_KEY_ID,
      issuerId: process.env.ASC_ISSUER_ID,
      keyPath: path.resolve(process.env.ASC_KEY_PATH),
    };
  }
  for (const file of configCandidates()) {
    if (!fs.existsSync(file)) continue;
    let obj;
    try {
      obj = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (e) {
      throw new Error(`設定の読み込みに失敗: ${file}\n${e.message}`);
    }
    const cfg = pickFromFile(obj, path.dirname(file), profileName);
    if (cfg) return cfg;
  }
  throw new Error(
    profileName
      ? `プロファイル "${profileName}" が見つかりません（~/.asc/config.json などを確認）。`
      : "認証情報が未設定です。~/.asc/config.json か ./.asc.json か環境変数を設定してください（README参照）。",
  );
}

// 設定ファイルに定義されたプロファイル一覧を集める（profiles コマンド用）。
function listProfiles() {
  const found = [];
  for (const file of configCandidates()) {
    if (!fs.existsSync(file)) continue;
    let obj;
    try {
      obj = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch {
      continue;
    }
    if (obj.profiles) {
      for (const name of Object.keys(obj.profiles)) {
        found.push(`${name}${obj.default === name ? " (default)" : ""}\t${file}`);
      }
    } else if (obj.keyId) {
      found.push(`(single)\t${file}`);
    }
  }
  return found;
}

function b64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

// ASC 用 JWT（ES256, aud=appstoreconnect-v1, 有効20分）を生成。
function makeToken(cfg) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: cfg.keyId, typ: "JWT" };
  const payload = {
    iss: cfg.issuerId,
    iat: now,
    exp: now + 20 * 60,
    aud: "appstoreconnect-v1",
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = crypto.createPrivateKey(fs.readFileSync(cfg.keyPath));
  // ES256 は JOSE の raw(R||S) 形式が必要。DDR ではなく ieee-p1363 を指定。
  const sig = crypto.sign("sha256", Buffer.from(signingInput), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${signingInput}.${b64url(sig)}`;
}

// ---------- APIリクエスト ----------

async function api(method, endpoint, { token, query, body } = {}) {
  const url = new URL(endpoint.startsWith("http") ? endpoint : BASE + endpoint);
  if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const buf = Buffer.from(await res.arrayBuffer());
  const ctype = res.headers.get("content-type") || "";
  if (!res.ok) {
    let detail = buf.toString("utf8");
    try {
      detail = JSON.stringify(JSON.parse(detail), null, 2);
    } catch {
      /* テキストのまま */
    }
    throw new Error(`API ${res.status} ${res.statusText}\n${detail}`);
  }
  if (ctype.includes("application/json") || ctype.includes("vnd.api+json")) {
    return JSON.parse(buf.toString("utf8"));
  }
  return buf; // gz レポート等のバイナリ
}

// ---------- 出力ヘルパ ----------

function printRows(rows) {
  if (!rows.length) {
    console.log("(該当なし)");
    return;
  }
  for (const r of rows) console.log(r);
}

function requireArg(val, usage) {
  if (val === undefined || val === null || val === "") {
    throw new Error(`使い方: ${usage}`);
  }
}

// 書き込みボディの解釈: '-'=標準入力 / 既存ファイルパス / それ以外はJSON文字列。
function readBodyArg(arg) {
  if (arg === undefined) return null;
  let raw;
  if (arg === "-") raw = fs.readFileSync(0, "utf8");
  else if (fs.existsSync(arg)) raw = fs.readFileSync(arg, "utf8");
  else raw = arg;
  try {
    return JSON.parse(raw);
  } catch (e) {
    throw new Error(`ボディのJSON解析に失敗: ${e.message}`);
  }
}

function describeRequest(method, endpoint, body) {
  const url = endpoint.startsWith("http") ? endpoint : BASE + endpoint;
  return `${method} ${url}\n${body ? JSON.stringify(body, null, 2) : "(body なし)"}`;
}

// 書き込みの共通実行。既定はドライラン（送信せず内容表示）。--yes で実送信。
async function runWrite(method, endpoint, body, cfg) {
  if (!EXECUTE) {
    console.log("[DRY-RUN] 送信しません。実行するには --yes を付けてください。\n");
    console.log(describeRequest(method, endpoint, body));
    return;
  }
  const token = makeToken(cfg);
  const res = await api(method, endpoint, { token, body });
  console.log(res ? JSON.stringify(res, null, 2) : "(204 No Content)");
}

// ---------- コマンド ----------

const commands = {
  async token(cfg) {
    console.log(makeToken(cfg));
  },

  async apps(cfg) {
    const token = makeToken(cfg);
    const data = await api("GET", "/v1/apps", { token, query: { limit: "200" } });
    printRows(
      (data.data || []).map((a) => {
        const at = a.attributes || {};
        return `${a.id}\t${at.name}\t${at.bundleId}\t[${at.sku || ""}]`;
      }),
    );
  },

  async builds(cfg, appId) {
    if (!appId) throw new Error("使い方: builds <appId>");
    const token = makeToken(cfg);
    const data = await api("GET", "/v1/builds", {
      token,
      query: { "filter[app]": appId, limit: "50", sort: "-version" },
    });
    printRows(
      (data.data || []).map((b) => {
        const at = b.attributes || {};
        return `${b.id}\tv${at.version}\t${at.processingState}\t${at.uploadedDate || ""}`;
      }),
    );
  },

  async iaps(cfg, appId) {
    if (!appId) throw new Error("使い方: iaps <appId>");
    const token = makeToken(cfg);
    const data = await api("GET", `/v1/apps/${appId}/inAppPurchasesV2`, {
      token,
      query: { limit: "200" },
    });
    printRows(
      (data.data || []).map((p) => {
        const at = p.attributes || {};
        return `${p.id}\t${at.productId}\t${at.inAppPurchaseType}\t${at.state}\t${at.name}`;
      }),
    );
  },

  async subgroups(cfg, appId) {
    if (!appId) throw new Error("使い方: subgroups <appId>");
    const token = makeToken(cfg);
    const data = await api("GET", `/v1/apps/${appId}/subscriptionGroups`, {
      token,
      query: { limit: "200" },
    });
    printRows(
      (data.data || []).map((g) => `${g.id}\t${(g.attributes || {}).referenceName}`),
    );
  },

  async subs(cfg, groupId) {
    if (!groupId) throw new Error("使い方: subs <subscriptionGroupId>");
    const token = makeToken(cfg);
    const data = await api("GET", `/v1/subscriptionGroups/${groupId}/subscriptions`, {
      token,
      query: { limit: "200" },
    });
    printRows(
      (data.data || []).map((s) => {
        const at = s.attributes || {};
        return `${s.id}\t${at.productId}\t${at.state}\t${at.subscriptionPeriod || ""}\t${at.name}`;
      }),
    );
  },

  async get(cfg, endpoint, ...kv) {
    if (!endpoint) throw new Error("使い方: get <path> [key=value ...]");
    const token = makeToken(cfg);
    const query = Object.fromEntries(
      kv.map((pair) => {
        const i = pair.indexOf("=");
        return [pair.slice(0, i), pair.slice(i + 1)];
      }),
    );
    const data = await api("GET", endpoint, { token, query });
    console.log(JSON.stringify(data, null, 2));
  },

  async sales(cfg, vendorId) {
    if (!vendorId) throw new Error("使い方: sales <vendorNumber>");
    const token = makeToken(cfg);
    // 前日ぶんの日次サマリー（Appleは通常 前日以降が取得可能）。
    const d = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const report = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
    const gz = await api("GET", "/v1/salesReports", {
      token,
      query: {
        "filter[frequency]": "DAILY",
        "filter[reportType]": "SALES",
        "filter[reportSubType]": "SUMMARY",
        "filter[vendorNumber]": vendorId,
        "filter[reportDate]": report,
      },
    });
    const tsv = gunzipSync(gz).toString("utf8");
    const out = path.join(HERE, `sales-${report}.tsv`);
    fs.writeFileSync(out, tsv);
    console.log(`保存: ${out}\n---\n${tsv.split("\n").slice(0, 5).join("\n")}`);
  },

  // ---- 書き込み系（既定ドライラン。--yes で実送信） ----

  async post(cfg, endpoint, bodyArg) {
    requireArg(endpoint, "post <path> <body.json|-|'{...}'> [--yes]");
    await runWrite("POST", endpoint, readBodyArg(bodyArg), cfg);
  },

  async patch(cfg, endpoint, bodyArg) {
    requireArg(endpoint, "patch <path> <body.json|-|'{...}'> [--yes]");
    await runWrite("PATCH", endpoint, readBodyArg(bodyArg), cfg);
  },

  async delete(cfg, endpoint) {
    requireArg(endpoint, "delete <path> [--yes]");
    await runWrite("DELETE", endpoint, null, cfg);
  },

  async versions(cfg, appId) {
    requireArg(appId, "versions <appId>");
    const token = makeToken(cfg);
    const data = await api("GET", `/v1/apps/${appId}/appStoreVersions`, {
      token,
      query: { limit: "20" },
    });
    printRows(
      (data.data || []).map((v) => {
        const at = v.attributes || {};
        return `${v.id}\t${at.versionString}\t${at.appStoreState}\t${at.platform}`;
      }),
    );
  },

  // 編集可能なバージョンの「新機能(What's New)」を指定ロケールで更新する（ガイド付き）。
  // 例: asc whatsnew 12345 ja "軽微な改善とバグ修正。" --yes
  async whatsnew(cfg, appId, locale, text) {
    requireArg(appId, 'whatsnew <appId> <locale> "<text>" [--yes]');
    requireArg(locale, 'whatsnew <appId> <locale> "<text>" [--yes]');
    requireArg(text, 'whatsnew <appId> <locale> "<text>" [--yes]');
    const token = makeToken(cfg);
    // 編集可能な状態のバージョンを探す。
    const editable = new Set([
      "PREPARE_FOR_SUBMISSION",
      "DEVELOPER_REJECTED",
      "REJECTED",
      "METADATA_REJECTED",
      "WAITING_FOR_REVIEW",
      "INVALID_BINARY",
    ]);
    const vers = await api("GET", `/v1/apps/${appId}/appStoreVersions`, {
      token,
      query: { limit: "20" },
    });
    const ver = (vers.data || []).find((v) =>
      editable.has((v.attributes || {}).appStoreState),
    );
    if (!ver) {
      throw new Error(
        "編集可能なバージョンが見つかりません（審査中でない準備中のバージョンが必要）。",
      );
    }
    // 該当ロケールのローカライズを探す。
    const locs = await api(
      "GET",
      `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`,
      { token, query: { limit: "50" } },
    );
    const loc = (locs.data || []).find(
      (l) => (l.attributes || {}).locale === locale,
    );
    if (!loc) {
      throw new Error(
        `ロケール ${locale} のローカライズがありません。先に App Store Connect で追加してください。`,
      );
    }
    console.log(`対象: version ${ver.attributes.versionString} / locale ${locale} / loc ${loc.id}`);
    await runWrite(
      "PATCH",
      `/v1/appStoreVersionLocalizations/${loc.id}`,
      {
        data: {
          type: "appStoreVersionLocalizations",
          id: loc.id,
          attributes: { whatsNew: text },
        },
      },
      cfg,
    );
  },

  async profiles() {
    const rows = listProfiles();
    if (!rows.length) {
      console.log(
        "プロファイル未設定です。~/.asc/config.json か ./.asc.json を作成してください（README参照）。",
      );
      return;
    }
    console.log("name\tsource");
    printRows(rows);
  },

  async help() {
    console.log(HELP);
  },
};

const HELP = `App Store Connect API CLI  ( asc <command> [--profile <name>] )

  asc apps                       アプリ一覧（appId確認）
  asc iaps <appId>               App内課金一覧
  asc subgroups <appId>          サブスクグループ一覧
  asc subs <subscriptionGroupId> グループ内サブスク一覧
  asc builds <appId>             ビルド一覧
  asc versions <appId>           App Storeバージョン一覧（状態確認）
  asc get <path> [key=value ...] 任意GET（例: asc get /v1/apps limit=5）
  asc sales <vendorNumber>       売上サマリー(前日)
  asc token                      JWT出力（curl等のデバッグ用）
  asc profiles                   設定済みプロファイル一覧

  --- 書き込み系（既定ドライラン。実送信は --yes を付ける）---
  asc post <path> <body.json|-|'{...}'>   作成（例: 課金・価格・提出）
  asc patch <path> <body.json|-|'{...}'>  更新
  asc delete <path>                        削除
  asc whatsnew <appId> <locale> "<text>"   新機能テキストを更新（ガイド付き）

グローバル導入すると "asc apps" で呼べる（未導入なら "node scripts/asc/asc.mjs apps"）。
  cd scripts/asc && npm link

認証（使い回し）:
  ~/.asc/config.json を1つ用意すれば、どのプロジェクトからでも使える。
  複数Appleアカウントは profiles を分け、--profile <name> で切替。
  詳細は scripts/asc/README.md
`;

// ---------- エントリ ----------

const NO_AUTH = new Set(["help", "profiles"]);

async function main() {
  const argv = process.argv.slice(2);
  // --profile / -p をどこにあっても抽出（残りをコマンド＋引数とする）。
  let profileName = process.env.ASC_PROFILE || null;
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--profile" || a === "-p") profileName = argv[++i];
    else if (a.startsWith("--profile=")) profileName = a.slice("--profile=".length);
    else if (a === "--yes" || a === "--execute" || a === "-y") EXECUTE = true;
    else rest.push(a);
  }
  const [cmd, ...args] = rest;
  if (!cmd || cmd === "help" || cmd === "-h" || cmd === "--help") {
    console.log(HELP);
    return;
  }
  const fn = commands[cmd];
  if (!fn) {
    console.error(`不明なコマンド: ${cmd}\n`);
    console.log(HELP);
    process.exit(1);
  }
  const cfg = NO_AUTH.has(cmd) ? null : loadConfig(profileName);
  await fn(cfg, ...args);
}

main().catch((err) => {
  console.error(String(err.message || err));
  process.exit(1);
});
