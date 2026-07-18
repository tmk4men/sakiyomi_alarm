// 共有ライブラリ（setup-iap.mjs / setup-metadata.mjs が使う）。
//   - 認証情報の解決（~/.asc/config.json など。asc.mjs と同じ探索）
//   - JWT 生成・API 呼び出し
//   - アプリ固有設定（asc.config.json）の読み込みと URL プレースホルダ展開
//
// これにより setup スクリプト本体はアプリ非依存になり、二度と編集不要。
// アプリ固有の値は asc.config.json 側だけで管理する。

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const BASE = "https://api.appstoreconnect.apple.com";

// ---------- 認証（Apple アカウント＝チーム単位。全アプリで使い回し） ----------
export function loadAuth() {
  if (process.env.ASC_KEY_ID && process.env.ASC_ISSUER_ID && process.env.ASC_KEY_PATH) {
    return {
      keyId: process.env.ASC_KEY_ID,
      issuerId: process.env.ASC_ISSUER_ID,
      keyPath: path.resolve(process.env.ASC_KEY_PATH),
    };
  }
  for (const f of [
    path.join(process.cwd(), ".asc.json"),
    path.join(os.homedir(), ".asc", "config.json"),
    path.join(os.homedir(), ".asc.json"),
  ]) {
    if (!fs.existsSync(f)) continue;
    const c = JSON.parse(fs.readFileSync(f, "utf8"));
    const p = c.profiles ? c.profiles[c.default || Object.keys(c.profiles)[0]] : c;
    if (p && p.keyId && p.issuerId && p.keyPath) {
      const kp = path.isAbsolute(p.keyPath) ? p.keyPath : path.resolve(path.dirname(f), p.keyPath);
      return { keyId: p.keyId, issuerId: p.issuerId, keyPath: kp };
    }
  }
  throw new Error("認証情報が見つかりません（~/.asc/config.json を用意してください。README参照）。");
}

function b64url(x) {
  return Buffer.from(x).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

export function makeToken() {
  const cfg = loadAuth();
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: "ES256", kid: cfg.keyId, typ: "JWT" }));
  const p = b64url(JSON.stringify({ iss: cfg.issuerId, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" }));
  const key = crypto.createPrivateKey(fs.readFileSync(cfg.keyPath));
  const sig = crypto.sign("sha256", Buffer.from(`${h}.${p}`), { key, dsaEncoding: "ieee-p1363" });
  return `${h}.${p}.${b64url(sig)}`;
}

// トークンは1回のプロセスで使い回す（20分有効）。
let _tok = null;
export async function api(method, endpoint, body) {
  if (!_tok) _tok = makeToken();
  const res = await fetch(BASE + endpoint, {
    method,
    headers: { Authorization: `Bearer ${_tok}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const msg = json?.errors?.map((e) => `${e.status} ${e.title}: ${e.detail}`).join("\n") || text;
    throw new Error(`${method} ${endpoint}\n${msg}`);
  }
  return json;
}

// ---------- アプリ固有設定（asc.config.json）の読み込み ----------
//
// 探索順:
//   1) コマンド引数で渡した .json のパス（例: setup-iap ./asc.config.json）
//   2) 環境変数 ASC_APP_CONFIG
//   3) ./asc.config.json（実行中ディレクトリ）
//   4) <このスクリプトと同じ場所>/asc.config.json
//
// appId は「数字だけの引数」で上書きできる（config.appId より優先）。
export function resolveConfigPath(argv, here) {
  const jsonArg = argv.find((a) => !a.startsWith("-") && /\.json$/i.test(a));
  const candidates = [
    jsonArg,
    process.env.ASC_APP_CONFIG,
    path.join(process.cwd(), "asc.config.json"),
    here && path.join(here, "asc.config.json"),
  ].filter(Boolean);
  for (const c of candidates) {
    if (fs.existsSync(c)) return path.resolve(c);
  }
  return null;
}

// 文字列中の ${BASE_URL} などを実値に展開する（description/reviewNotes 等で使える）。
function expand(str, vars) {
  return str.replace(/\$\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));
}
function deepExpand(value, vars) {
  if (typeof value === "string") return expand(value, vars);
  if (Array.isArray(value)) return value.map((v) => deepExpand(v, vars));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, deepExpand(v, vars)]));
  }
  return value;
}

// config を読み、URL 系を導出し、プレースホルダを展開して返す。
export function loadAppConfig(argv, here) {
  const p = resolveConfigPath(argv, here);
  if (!p) {
    throw new Error(
      "アプリ設定 asc.config.json が見つかりません。\n" +
        "  使い方: <script> ./asc.config.json [--yes]   （または実行フォルダに asc.config.json を置く）\n" +
        "  雛形: scripts/asc/asc.config.example.json をコピーして値を埋めてください。",
    );
  }
  let cfg;
  try {
    cfg = JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    throw new Error(`設定の読み込みに失敗: ${p}\n${e.message}`);
  }

  // appId: 数字だけの引数で上書き可。
  const numArg = argv.find((a) => /^\d+$/.test(a));
  const appId = numArg || cfg.appId;
  if (!appId) throw new Error("appId がありません（config の appId か、数字の引数で指定）。");

  // URL 導出（baseUrl を1つ変えれば privacy/terms/support が揃う）。
  const baseUrl = (cfg.urls && cfg.urls.baseUrl) || "";
  const vars = {
    BASE_URL: baseUrl,
    PRIVACY_URL: baseUrl ? `${baseUrl}/privacy.html` : "",
    TERMS_URL: baseUrl ? `${baseUrl}/terms.html` : "",
    SUPPORT_URL: baseUrl ? `${baseUrl}/support.html` : "",
    CONTACT_EMAIL: (cfg.urls && cfg.urls.contactEmail) || "",
  };

  const expanded = deepExpand(cfg, vars);
  return {
    path: p,
    appId,
    locale: expanded.locale || "ja",
    category: expanded.category || null,
    urls: { ...expanded.urls, ...vars },
    plan: expanded.plan || null,
    copy: expanded.copy || null,
  };
}
