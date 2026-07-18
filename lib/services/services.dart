import '../data/app_store.dart';
import 'notification_service.dart';
import 'billing_service.dart';

/// アプリ全体で共有する単一インスタンス（main で初期化）。
late AppStore appStore;
late NotificationService notificationService;
late BillingService billingService;
