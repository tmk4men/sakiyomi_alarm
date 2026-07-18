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
const int kSnoozeIdBase = 900000000;

/// 通常アラームのベースID = 日付(yyyyMMdd)。擬似ループの各回は ベース*10+r。
int _baseId(String dateKey) => int.parse(dateKey.replaceAll('-', ''));
int _repeatId(String dateKey, int r) => _baseId(dateKey) * 10 + r;
int _snoozeId(int millis) => kSnoozeIdBase + (millis % 90000000);

String _channelIdFor(String soundId) =>
    soundId == BuiltinSounds.defaultId ? kChannelId : 'sakiyomi_alarms_$soundId';

NotificationDetails _details(bool vibrate, String soundId) {
  final custom = soundId != BuiltinSounds.defaultId;
  return NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      sound: custom ? '$soundId.caf' : null,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: kCategoryId,
    ),
    android: AndroidNotificationDetails(
      _channelIdFor(soundId),
      soundId == BuiltinSounds.defaultId ? kChannelName : 'アラーム (${BuiltinSounds.nameFor(soundId)})',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      enableVibration: vibrate,
      playSound: true,
      sound: custom ? RawResourceAndroidNotificationSound(soundId) : null,
      actions: const [
        AndroidNotificationAction('stop', '止める'),
        AndroidNotificationAction('snooze', 'スヌーズ'),
      ],
    ),
  );
}

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
  final soundId = (data['sound'] as String?) ?? BuiltinSounds.defaultId;
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: snooze));

  try {
    await plugin.zonedSchedule(
      id: _snoozeId(when.millisecondsSinceEpoch),
      title: label,
      body: 'スヌーズ中 — $snooze分後',
      scheduledDate: when,
      notificationDetails: _details(vibrate, soundId),
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
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      iOS: DarwinInitializationSettings(),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  if (response.actionId == 'snooze') {
    try {
      tzdata.initializeTimeZones();
      final dynamic res = await FlutterTimezone.getLocalTimezone();
      final name = res is String ? res : (res as dynamic).identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {}
    await _scheduleSnooze(plugin, response.payload);
  } else if (response.actionId == 'stop') {
    await _cancelRepeats(plugin, response.payload);
  }
}

/// 擬似ループの残り通知をキャンセルして鳴りやませる。
Future<void> _cancelRepeats(
    FlutterLocalNotificationsPlugin plugin, String? payload) async {
  if (payload == null) return;
  try {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final key = data['date'] as String?;
    if (key == null) return;
    for (var r = 0; r <= 9; r++) {
      try {
        await plugin.cancel(id: _repeatId(key, r));
      } catch (_) {}
    }
  } catch (_) {}
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

    // 音源ごとに Android チャンネルを用意（Android8+ は音がチャンネル依存のため）。
    final android8 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android8 != null) {
      for (final s in BuiltinSounds.all) {
        await android8.createNotificationChannel(AndroidNotificationChannel(
          _channelIdFor(s.id),
          s.id == BuiltinSounds.defaultId ? kChannelName : 'アラーム (${s.name})',
          description: '設定した時刻に起こすアラーム通知',
          importance: Importance.max,
          playSound: true,
          sound: s.id == BuiltinSounds.defaultId
              ? null
              : RawResourceAndroidNotificationSound(s.id),
        ));
      }
    }

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
    } else if (response.actionId == 'stop') {
      await _cancelRepeats(_plugin, response.payload);
    }
  }

  Future<void> refreshAndReschedule(AppStore store) async {
    await _applyLocalTimezone();
    await rescheduleAll(store);
  }

  /// 予定に基づき通知を貼り直す。直近のアラームには擬似ループ（連続通知）を付ける。
  Future<void> rescheduleAll(AppStore store) async {
    if (!_ready) return;

    // 既存の通常アラームのみキャンセル（スヌーズは温存）。1件ずつ try/catch。
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
      if (store.isLocked(key)) continue;
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
          soundId: r.soundId,
        ),
      ));
    }

    upcoming.sort((a, b) => a.when.compareTo(b.when));

    var scheduled = 0;
    for (var i = 0; i < upcoming.length; i++) {
      if (scheduled >= kMaxScheduledAlarms) break;
      final item = upcoming[i];
      final payload = jsonEncode({
        'date': item.alarm.key,
        'label': item.alarm.label,
        'snooze': item.alarm.snooze,
        'vibrate': item.alarm.vibrate,
        'sound': item.alarm.soundId,
      });
      // 直近のアラームだけ擬似ループ（連続通知）を付ける（64個上限の保護）。
      final reps = i < kLoopAlarmsAhead ? kAlarmRepeatCount : 0;
      for (var r = 0; r <= reps; r++) {
        if (scheduled >= kMaxScheduledAlarms) break;
        final when = item.when.add(Duration(seconds: r * kAlarmRepeatIntervalSec));
        try {
          await _plugin.zonedSchedule(
            id: _repeatId(item.alarm.key, r),
            title: item.alarm.label,
            body: r == 0 ? '起きる時間です' : '起きる時間です（鳴動中）',
            scheduledDate: when,
            notificationDetails: _details(item.alarm.vibrate, item.alarm.soundId),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: payload,
          );
          scheduled++;
        } catch (e) {
          debugPrint('schedule failed ${item.alarm.key} r=$r: $e');
        }
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
  final String soundId;
  const ResolvedForNotif({
    required this.key,
    required this.label,
    required this.snooze,
    required this.vibrate,
    required this.soundId,
  });
}
