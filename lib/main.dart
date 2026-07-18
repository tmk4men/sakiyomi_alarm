import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/app_store.dart';
import 'services/services.dart';
import 'services/notification_service.dart';
import 'services/billing_service.dart';
import 'theme/app_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  appStore = AppStore();
  await appStore.load();

  // Webプレビュー限定: 空だと画面が寂しいのでサンプルの1週間を入れる（実機には影響なし）。
  if (kIsWeb && appStore.dayPlans.isEmpty) {
    await appStore.applyRotation(
      ['p_early', 'p_early', 'p_normal', 'p_off', 'p_normal', 'p_early', 'p_off'],
      7,
    );
  }

  notificationService = NotificationService();
  billingService = BillingService(appStore);

  // Web(プレビュー)ではネイティブプラグインが動かないため初期化をスキップ。
  if (!kIsWeb) {
    await notificationService.init();
    // 予定が変わるたびに通知を貼り直す。
    appStore.onScheduleChanged = () => notificationService.rescheduleAll(appStore);
    // 課金初期化は起動をブロックしない。
    billingService.init();
    // 初回スケジュール。
    await notificationService.rescheduleAll(appStore);
  }

  runApp(const SakiyomiApp());
}

class SakiyomiApp extends StatefulWidget {
  const SakiyomiApp({super.key});

  @override
  State<SakiyomiApp> createState() => _SakiyomiAppState();
}

class _SakiyomiAppState extends State<SakiyomiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 初回フレーム後に通知許可をリクエスト。
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await notificationService.requestPermissions();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 復帰時に端末タイムゾーンの変更（旅行等）へ追随して貼り直す。
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      notificationService.refreshAndReschedule(appStore);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appStore,
      builder: (context, _) {
        return MaterialApp(
          title: 'さきよみアラーム',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: appStore.themeMode,
          locale: const Locale('ja'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ja'), Locale('en')],
          home: const HomePage(),
        );
      },
    );
  }
}
