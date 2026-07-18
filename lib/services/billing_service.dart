import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants.dart';
import '../data/app_store.dart';

/// アプリ内課金の薄いラッパー。
///
/// 安全策: 権利(Pro)は購入が purchased / restored になったときのみ付与する。
/// キャンセル・エラー・保留では解放しない。
class BillingService extends ChangeNotifier {
  final AppStore store;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool purchasePending = false;
  String? lastError;
  List<ProductDetails> products = [];

  BillingService(this.store);

  ProductDetails? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> init() async {
    available = await _iap.isAvailable();
    if (!available) {
      notifyListeners();
      return;
    }
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        lastError = '課金エラー: $e';
        notifyListeners();
      },
    );
    await _queryProducts();
    // 起動時に既存購入を復元して権利を同期（復元・遅延反映の要）。
    await _iap.restorePurchases();
  }

  Future<void> _queryProducts() async {
    final resp = await _iap.queryProductDetails(Products.all.toSet());
    products = resp.productDetails;
    if (resp.error != null) {
      lastError = '商品情報の取得に失敗: ${resp.error!.message}';
    }
    notifyListeners();
  }

  Future<void> buy(ProductDetails product) async {
    if (!available) {
      lastError = '課金サービスに接続できません';
      notifyListeners();
      return;
    }
    final param = PurchaseParam(productDetails: product);
    try {
      // 自動更新サブスクは非消費型として購入する。
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      lastError = '購入を開始できませんでした: $e';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (!available) return;
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          purchasePending = true;
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          // キャンセルは権利付与しない（無料解放バグを防ぐ核心）。
          purchasePending = false;
          lastError = '購入をキャンセルしました';
          notifyListeners();
          break;
        case PurchaseStatus.error:
          purchasePending = false;
          lastError = '購入に失敗しました: ${p.error?.message ?? ''}';
          notifyListeners();
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          purchasePending = false;
          if (_isValid(p)) {
            await store.setEntitlement(pro: true, productId: p.productID);
          }
          break;
      }
      // 保留完了が必要なものは必ず完了させる（未完了放置は返金/再通知の原因）。
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
    notifyListeners();
  }

  bool _isValid(PurchaseDetails p) {
    // 既知の制約: in_app_purchase 単体ではサブスクの有効期限・返金・解約後の
    // 失効を検出できない。付与済みの isPro はローカルに残り続ける。
    // 本番では StoreKit2(JWS) もしくはサーバーでのレシート/署名検証を追加し、
    // 期限切れ・取消・猶予期間を EntitlementRepository に同期すること。
    return Products.all.contains(p.productID);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
