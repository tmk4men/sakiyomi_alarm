import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/preset.dart';
import '../models/day_plan.dart';

String dateKeyOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// アプリ全体の状態と永続化を担う。UIは [AppStore] を監視して再描画する。
class AppStore extends ChangeNotifier {
  static const _kPresets = 'presets_v1';
  static const _kDayPlans = 'dayplans_v1';
  static const _kSettings = 'settings_v1';
  static const _kEntitlement = 'entitlement_v1';

  late SharedPreferences _prefs;

  List<Preset> presets = [];
  Map<String, DayPlan> dayPlans = {};
  ThemeMode themeMode = ThemeMode.system;
  int defaultSnooze = 5;

  bool isPro = false;
  String? proProductId;

  /// 予定変更後に通知を貼り直すためのフック（main で NotificationService を接続）。
  Future<void> Function()? onScheduleChanged;

  DateTime get today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  int daysFromToday(String dateKey) => parseDateKey(dateKey).difference(today).inDays;

  bool isLocked(String dateKey) =>
      !isPro && daysFromToday(dateKey) > kFreeDaysAhead;

  Preset? presetById(String? id) {
    if (id == null) return null;
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    // 各領域を個別に try/catch。破損キーがあってもアプリは起動する。
    try {
      final presetsRaw = _prefs.getString(_kPresets);
      if (presetsRaw != null) {
        final list = jsonDecode(presetsRaw) as List<dynamic>;
        presets = list
            .map((e) => Preset.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      presets = [];
    }
    if (presets.isEmpty) {
      presets = _defaultPresets();
      await _savePresets();
    }

    try {
      final plansRaw = _prefs.getString(_kDayPlans);
      if (plansRaw != null) {
        final map = jsonDecode(plansRaw) as Map<String, dynamic>;
        dayPlans = map.map(
            (k, v) => MapEntry(k, DayPlan.fromJson(v as Map<String, dynamic>)));
      }
    } catch (_) {
      dayPlans = {};
    }

    try {
      final settingsRaw = _prefs.getString(_kSettings);
      if (settingsRaw != null) {
        final s = jsonDecode(settingsRaw) as Map<String, dynamic>;
        final tm = (s['themeMode'] as int?) ?? 0;
        themeMode = (tm >= 0 && tm < ThemeMode.values.length)
            ? ThemeMode.values[tm]
            : ThemeMode.system;
        defaultSnooze = (s['defaultSnooze'] as int?) ?? 5;
      }
    } catch (_) {
      themeMode = ThemeMode.system;
      defaultSnooze = 5;
    }

    try {
      final entRaw = _prefs.getString(_kEntitlement);
      if (entRaw != null) {
        final e = jsonDecode(entRaw) as Map<String, dynamic>;
        isPro = (e['isPro'] as bool?) ?? false;
        proProductId = e['productId'] as String?;
      }
    } catch (_) {
      isPro = false;
      proProductId = null;
    }

    notifyListeners();
  }

  // 変更可能(growable)なリストで返す。const リストだと add/removeWhere でクラッシュする。
  List<Preset> _defaultPresets() => [
        const Preset(id: 'p_normal', name: '通常', hour: 7, minute: 0, colorIndex: 0),
        const Preset(id: 'p_early', name: '早番', hour: 5, minute: 30, colorIndex: 1),
        const Preset(id: 'p_off', name: '休み', hour: null, minute: null, colorIndex: 4),
      ];

  // ---- resolve ----

  /// その日に実際に鳴るアラーム。休み・未設定の場合は null。
  ResolvedAlarm? resolve(String dateKey) {
    final plan = dayPlans[dateKey];
    if (plan == null) return null;
    final preset = presetById(plan.presetId);
    if (plan.hasOverride) {
      final useP = preset != null && !preset.isDayOff;
      return ResolvedAlarm(
        dateKey: dateKey,
        hour: plan.overrideHour!,
        minute: plan.overrideMinute!,
        label: useP ? preset.name : '個別',
        colorIndex: useP ? preset.colorIndex : 0,
        snoozeMinutes: preset?.snoozeMinutes ?? defaultSnooze,
        vibrate: preset?.vibrate ?? true,
        isOverride: true,
      );
    }
    if (preset != null && !preset.isDayOff) {
      return ResolvedAlarm(
        dateKey: dateKey,
        hour: preset.hour!,
        minute: preset.minute!,
        label: preset.name,
        colorIndex: preset.colorIndex,
        snoozeMinutes: preset.snoozeMinutes,
        vibrate: preset.vibrate,
        isOverride: false,
      );
    }
    return null;
  }

  /// 「休み（アラームなし）」に塗られた日か。
  bool dayIsOff(String dateKey) {
    final plan = dayPlans[dateKey];
    if (plan == null || plan.hasOverride) return false;
    final p = presetById(plan.presetId);
    return p != null && p.isDayOff;
  }

  /// 直近の未来アラーム（今より後）。
  ({DateTime when, ResolvedAlarm alarm})? nextAlarm() {
    final now = DateTime.now();
    ({DateTime when, ResolvedAlarm alarm})? best;
    for (final key in dayPlans.keys) {
      if (isLocked(key)) continue; // 非Proのロック日は予約されないので次候補にもしない
      final r = resolve(key);
      if (r == null) continue;
      final d = parseDateKey(key);
      final when = DateTime(d.year, d.month, d.day, r.hour, r.minute);
      if (!when.isAfter(now)) continue;
      if (best == null || when.isBefore(best.when)) {
        best = (when: when, alarm: r);
      }
    }
    return best;
  }

  /// 指定月の集計（アラーム日数・休み日数・設定できる空き日数）。
  ({int set, int off, int empty}) monthSummary(int year, int month) {
    final dim = DateTime(year, month + 1, 0).day;
    int set = 0, off = 0, empty = 0;
    for (var d = 1; d <= dim; d++) {
      final key = dateKeyOf(DateTime(year, month, d));
      if (resolve(key) != null) {
        set++;
      } else if (dayIsOff(key)) {
        off++;
      } else {
        final diff = daysFromToday(key);
        if (diff >= 0 && diff <= kFreeDaysAhead) empty++;
      }
    }
    return (set: set, off: off, empty: empty);
  }

  // ---- mutations ----

  Future<void> assignPreset(String dateKey, String presetId) async {
    if (isLocked(dateKey)) return; // 無料枠の制限をストア層でも強制
    dayPlans[dateKey] = DayPlan(date: dateKey, presetId: presetId);
    await _commit();
  }

  /// ドラッグ塗り用: UIだけ即時更新し、永続化と通知再スケジュールは遅延する。
  /// 変更があれば true。ドラッグ終了時に [commitPaint] を必ず呼ぶこと。
  bool paintPresetLive(String dateKey, String presetId) {
    if (isLocked(dateKey)) return false;
    final plan = dayPlans[dateKey];
    if (plan != null && plan.presetId == presetId && !plan.hasOverride) {
      return false; // 既に同じ
    }
    dayPlans[dateKey] = DayPlan(date: dateKey, presetId: presetId);
    notifyListeners();
    return true;
  }

  /// ドラッグ塗り確定: まとめて永続化＋再スケジュール。
  Future<void> commitPaint() async {
    await _commit();
  }

  Future<void> setOverride(String dateKey, int hour, int minute) async {
    if (isLocked(dateKey)) return;
    final existing = dayPlans[dateKey];
    dayPlans[dateKey] = DayPlan(
      date: dateKey,
      presetId: existing?.presetId,
      overrideHour: hour,
      overrideMinute: minute,
    );
    await _commit();
  }

  Future<void> clearDay(String dateKey) async {
    dayPlans.remove(dateKey);
    await _commit();
  }

  Future<void> applyRotation(List<String> presetIds, int days) async {
    if (presetIds.isEmpty) return;
    for (var i = 0; i < days; i++) {
      final d = today.add(Duration(days: i));
      final key = dateKeyOf(d);
      dayPlans[key] = DayPlan(date: key, presetId: presetIds[i % presetIds.length]);
    }
    await _commit();
  }

  Future<void> upsertPreset(Preset preset) async {
    final idx = presets.indexWhere((p) => p.id == preset.id);
    if (idx >= 0) {
      presets[idx] = preset;
    } else {
      presets.add(preset);
    }
    await _savePresets();
    await _commit();
  }

  Future<void> deletePreset(String id) async {
    presets.removeWhere((p) => p.id == id);
    // そのプリセットを使っていた日の割り当ては解除する。
    dayPlans.removeWhere((_, plan) => plan.presetId == id && !plan.hasOverride);
    await _savePresets();
    await _commit();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setDefaultSnooze(int minutes) async {
    defaultSnooze = minutes;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setEntitlement({required bool pro, String? productId}) async {
    isPro = pro;
    proProductId = productId;
    await _prefs.setString(
      _kEntitlement,
      jsonEncode({'isPro': pro, 'productId': productId}),
    );
    await _commit();
  }

  // ---- persistence ----

  Future<void> _savePresets() async => _prefs.setString(
      _kPresets, jsonEncode(presets.map((e) => e.toJson()).toList()));

  Future<void> _saveDayPlans() async => _prefs.setString(
      _kDayPlans, jsonEncode(dayPlans.map((k, v) => MapEntry(k, v.toJson()))));

  Future<void> _saveSettings() async => _prefs.setString(
      _kSettings,
      jsonEncode({'themeMode': themeMode.index, 'defaultSnooze': defaultSnooze}));

  /// 保存 → 監視者に通知 → 通知の再スケジュール。
  Future<void> _commit() async {
    await _saveDayPlans();
    notifyListeners();
    if (onScheduleChanged != null) {
      await onScheduleChanged!();
    }
  }
}
