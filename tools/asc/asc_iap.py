#!/usr/bin/env python3
"""
App Store Connect API で さきよみアラームの課金商品を作成するツール。

- 月額サブスク: sakiyomi_pro_monthly (¥400)
- 買い切り(非消費型): sakiyomi_pro_lifetime (¥900)

鍵は環境変数で渡す（コードに含めない）。postura で使っている .p8 を流用可。

必要:
  pip install pyjwt[crypto] requests

環境変数:
  ASC_KEY_ID      … App Store Connect APIキーの Key ID
  ASC_ISSUER_ID   … Issuer ID
  ASC_KEY_PATH    … AuthKey_XXXX.p8 のパス
  BUNDLE_ID       … 省略時 app.sakiyomi.alarm

使い方（Mac）:
  python3 asc_iap.py verify    # 認証確認・アプリ検索・既存商品の一覧（作成しない）
  python3 asc_iap.py create    # 商品を作成
"""

import os
import sys
import time
import json
import urllib.request
import urllib.error

try:
    import jwt  # PyJWT
except ImportError:
    sys.exit("pip install 'pyjwt[crypto]' requests が必要です")

BASE = "https://api.appstoreconnect.apple.com"
KEY_ID = os.environ.get("ASC_KEY_ID")
ISSUER_ID = os.environ.get("ASC_ISSUER_ID")
KEY_PATH = os.environ.get("ASC_KEY_PATH")
BUNDLE_ID = os.environ.get("BUNDLE_ID", "app.sakiyomi.alarm")

MONTHLY_PRODUCT_ID = "sakiyomi_pro_monthly"
MONTHLY_NAME = "さきよみ Pro（月額）"
MONTHLY_YEN = "400"

LIFETIME_PRODUCT_ID = "sakiyomi_pro_lifetime"
LIFETIME_NAME = "さきよみ Pro（買い切り）"
LIFETIME_YEN = "900"

TERRITORY = "JPN"
GROUP_REF_NAME = "SakiyomiPro"


def token():
    if not (KEY_ID and ISSUER_ID and KEY_PATH):
        sys.exit("環境変数 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH を設定してください")
    with open(KEY_PATH, "r") as f:
        private_key = f.read()
    now = int(time.time())
    payload = {"iss": ISSUER_ID, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})


def api(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        raise SystemExit(f"APIエラー {e.code} {method} {path}\n{detail}")


def find_app_id():
    res = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    items = res.get("data", [])
    if not items:
        raise SystemExit(f"Bundle ID {BUNDLE_ID} のアプリが見つかりません（先にApp登録が必要）")
    app = items[0]
    print(f"App: {app['attributes'].get('name')}  id={app['id']}")
    return app["id"]


def verify():
    app_id = find_app_id()
    groups = api("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    print(f"サブスクグループ: {len(groups.get('data', []))} 件")
    for g in groups.get("data", []):
        print("  -", g["attributes"].get("referenceName"), g["id"])
        subs = api("GET", f"/v1/subscriptionGroups/{g['id']}/subscriptions")
        for s in subs.get("data", []):
            a = s["attributes"]
            print("      sub:", a.get("productId"), a.get("name"), a.get("state"))
    iaps = api("GET", f"/v1/apps/{app_id}/inAppPurchasesV2")
    print(f"買い切り/消費型IAP: {len(iaps.get('data', []))} 件")
    for i in iaps.get("data", []):
        a = i["attributes"]
        print("  -", a.get("productId"), a.get("name"), a.get("state"))


def ensure_subscription_group(app_id):
    groups = api("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    for g in groups.get("data", []):
        if g["attributes"].get("referenceName") == GROUP_REF_NAME:
            return g["id"]
    body = {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": GROUP_REF_NAME},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    res = api("POST", "/v1/subscriptionGroups", body)
    gid = res["data"]["id"]
    print("サブスクグループ作成:", gid)
    return gid


def create_monthly(group_id):
    body = {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "name": MONTHLY_NAME,
                "productId": MONTHLY_PRODUCT_ID,
                "subscriptionPeriod": "ONE_MONTH",
                "familySharable": False,
            },
            "relationships": {
                "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
            },
        }
    }
    res = api("POST", "/v1/subscriptions", body)
    sub_id = res["data"]["id"]
    print("サブスク作成:", MONTHLY_PRODUCT_ID, sub_id)

    # 表示名(ローカライズ)
    api("POST", "/v1/subscriptionLocalizations", {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {"name": "さきよみ Pro 月額", "locale": "ja"},
            "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sub_id}}},
        }
    })

    # 価格ポイント(¥400)を探して価格設定
    pp = api("GET", f"/v1/subscriptions/{sub_id}/pricePoints?filter[territory]={TERRITORY}&limit=200")
    point = _match_price_point(pp.get("data", []), MONTHLY_YEN)
    api("POST", "/v1/subscriptionPrices", {
        "data": {
            "type": "subscriptionPrices",
            "attributes": {"startDate": None, "preserveCurrentPrice": False},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point}},
            },
        }
    })
    print("  価格 ¥%s 設定" % MONTHLY_YEN)


def create_lifetime(app_id):
    body = {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": LIFETIME_NAME,
                "productId": LIFETIME_PRODUCT_ID,
                "inAppPurchaseType": "NON_CONSUMABLE",
            },
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    res = api("POST", "/v2/inAppPurchases", body)
    iap_id = res["data"]["id"]
    print("買い切りIAP作成:", LIFETIME_PRODUCT_ID, iap_id)

    api("POST", "/v1/inAppPurchaseLocalizations", {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"name": "さきよみ Pro 買い切り", "locale": "ja"},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
        }
    })

    pp = api("GET", f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]={TERRITORY}&limit=200")
    point = _match_price_point(pp.get("data", []), LIFETIME_YEN)
    # 価格スケジュール（手動価格）
    api("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price1}"}]},
            },
        },
        "included": [{
            "type": "inAppPurchasePrices",
            "id": "${price1}",
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point}},
            },
        }],
    })
    print("  価格 ¥%s 設定" % LIFETIME_YEN)


def _match_price_point(points, yen):
    for p in points:
        cp = p["attributes"].get("customerPrice")
        if cp in (yen, yen + ".000", yen + ".00"):
            return p["id"]
    # 完全一致が無ければ最も近い価格ポイントを選ぶ
    def price(p):
        try:
            return float(p["attributes"].get("customerPrice", "0"))
        except ValueError:
            return 0.0
    if not points:
        raise SystemExit("価格ポイントが取得できませんでした（territory/権限を確認）")
    nearest = min(points, key=lambda p: abs(price(p) - float(yen)))
    print(f"  注意: ¥{yen} の完全一致なし。最も近い ¥{nearest['attributes'].get('customerPrice')} を使用")
    return nearest["id"]


def create():
    app_id = find_app_id()
    group_id = ensure_subscription_group(app_id)
    create_monthly(group_id)
    create_lifetime(app_id)
    print("\n完了。App Store Connect で審査提出前にメタデータ/スクショを確認してください。")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if cmd == "verify":
        verify()
    elif cmd == "create":
        create()
    else:
        print(__doc__)
