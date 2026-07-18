import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../constants.dart';
import '../data/app_store.dart';

const String kChannelId = 'sakiyomi_alarms';
const String kChannelName = 'アラーム';
const String kCategoryId = 'sakiyomi_alarm';

/// スヌーズ通知のIDはこの値以上を使い、通常アラーム(=日付由来ID)と分離する。
/// 再スケジュール時に通常アラームだけをキャンセルし、スヌーズを消さないため。
const int kSnoozeIdBase = 900000000;

/// 通常アラームのID = 日付そのもの(yyyyMMdd)。1日1件で衝突しない。
int _mainId(String dateKey) => int.parse(dateKey.replaceAll('-', ''));

/// スヌーズ用の一意ID（予約枠を通常アラームと分離）。
int _snoozeId(int millis) => kSnoozeIdBase + (millis % 90000000);

NotificationDetails _details(bool vibrate) => NotificationDetails(
      iOS: const DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: kCategoryId,
      ),
      android: AndroidNotificationDetails(
        kChannelId,
        kChannelName,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        enableVibration: vibrate,
        actions: const [
          AndroidNotificationAction('stop', '止める'),
          AndroidNotificationAction('snooze', 'スヌーズ'),
        ],
      ),
    );

/// スヌーズ用の一発通知を（前面/背景どちらの isolate からも）予約する。
Future<void> _scheduleSnooze(
    FlutterLocalNotificationsPlugin plugin, String? payload) async {
  if (payload == null) return;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }
  final label = (data['label'] as String?) ?? 'アラーム';
  final snooze = (data['snooze'] as int?) ?? 5;
  final vibrate = (data['vibrate'] as bool?) ?? true;
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: snooze));

  try {
    await plugin.zonedSchedule(
      id: _snoozeId(when.millisecondsSinceEpoch),
      title: label,
      body: 'スヌーズ中 — $snooze分後',
      scheduledDate: when,
      notificationDetails: _details(vibrate),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  } catch (e) {
    debugPrint('snooze schedule failed: $e');
  }
}

/// 背景 isolate でのアクション応答（ロック画面のスヌーズ等）。
@pragma('vm:entry-point')
void notificationBackgroundResponse(NotificationResponse response) async {
  if (response.actionId == 'snooze') {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    try {
      tzdata.initializeTimeZones();
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      final name = res is String ? res : (res as dynamic).identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}
    await _scheduleSnooze(plugin, response.payload);
  }
}

/// ローカル通知でアラームを予約・管理するサービス。
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _applyLocalTimezone() async {
    String tzName = 'Asia/Tokyo';
    try {
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      if (res is String) {
        tzName = res;
      } else {
        tzName = (res as dynamic).identifier as String;
      }
    } catch (_) {}
    try {
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    }
  }

  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _applyLocalTimezone();

    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          kCategoryId,
          actions: [
            DarwinNotificationAction.plain('stop', '止める'),
            DarwinNotificationAction.plain('snooze', 'スヌーズ'),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
      ],
    );
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      settings: InitializationSettings(iOS: darwin, android: android),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundResponse,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      kChannelId,
      kChannelName,
      description: '設定した時刻に起こすアラーム通知',
      importance: Importance.max,
    ));

    _ready = true;
  }

  Future<bool> requestPermissions() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
          alert: true, badge: true, sound: true, critical: false);
      return granted ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  Future<void> _onResponse(NotificationResponse response) async {
    if (response.actionId == 'snooze') {
      await _scheduleSnooze(_plugin, response.payload);
    }
  }

  /// 端末タイムゾーンの変更（旅行等）に追随して貼り直す。アプリ復帰時に呼ぶ。
  Future<void> refreshAndReschedule(AppStore store) async {
    await _applyLocalTimezone();
    await rescheduleAll(store);
  }

  /// 予定に基づき、直近の未来アラームを（上限までまとめて）貼り直す。
  ///
  /// - 通常アラーム(ID<kSnoozeIdBase)だけを個別キャンセルし、スヌーズは消さない。
  /// - ロック(非Pro×8日目以降)の日は予約しない。
  /// - 1件ずつ try/catch し、途中失敗で全滅させない。
  Future<void> rescheduleAll(AppStore store) async {
    if (!_ready) return;

    // 既存の通常アラームのみキャンセル（スヌーズは温存）。
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id < kSnoozeIdBase) {
          try {
            await _plugin.cancel(id: p.id);
          } catch (e) {
            debugPrint('cancel ${p.id} failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('list pending failed: $e');
    }

    final now = tz.TZDateTime.now(tz.local);
    final upcoming = <({tz.TZDateTime when, ResolvedForNotif alarm})>[];

    for (final key in store.dayPlans.keys) {
      if (store.isLocked(key)) continue; // 非Proのロック日は鳴らさない
      final r = store.resolve(key);
      if (r == null) continue;
      final d = parseDateKey(key);
      final when =
          tz.TZDateTime(tz.local, d.year, d.month, d.day, r.hour, r.minute);
      if (!when.isAfter(now)) continue;
      upcoming.add((
        when: when,
        alarm: ResolvedForNotif(
          key: key,
          label: r.label,
          snooze: r.snoozeMinutes,
          vibrate: r.vibrate,
        ),
      ));
    }

    upcoming.sort((a, b) => a.when.compareTo(b.when));
    final limited = upcoming.take(kMaxScheduledAlarms);

    for (final item in limited) {
      final payload = jsonEncode({
        'date': item.alarm.key,
        'label': item.alarm.label,
        'snooze': item.alarm.snooze,
        'vibrate': item.alarm.vibrate,
      });
      try {
        await _plugin.zonedSchedule(
          id: _mainId(item.alarm.key),
          title: item.alarm.label,
          body: '起きる時間です',
          scheduledDate: item.when,
          notificationDetails: _details(item.alarm.vibrate),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload,
        );
      } catch (e) {
        // 権限なし/上限超過/OSエラー等。1件失敗しても他は続行する。
        debugPrint('schedule failed for ${item.alarm.key}: $e');
      }
    }
  }
}

/// 通知スケジュール用に必要な最小情報。
class ResolvedForNotif {
  final String key;
  final String label;
  final int snooze;
  final bool vibrate;
  const ResolvedForNotif({
    required this.key,
    required this.label,
    required this.snooze,
    required this.vibrate,
  });
}
