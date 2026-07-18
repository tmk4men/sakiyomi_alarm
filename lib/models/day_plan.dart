/// カレンダーの1日に割り当てられた設定。
/// [presetId] でプリセットを割り当て、[overrideHour]/[overrideMinute] で
/// 「その日だけの時刻」を上書きできる。
class DayPlan {
  final String date; // 'yyyy-MM-dd'
  final String? presetId;
  final int? overrideHour;
  final int? overrideMinute;

  const DayPlan({
    required this.date,
    this.presetId,
    this.overrideHour,
    this.overrideMinute,
  });

  bool get hasOverride => overrideHour != null && overrideMinute != null;

  DayPlan copyWith({
    String? presetId,
    int? overrideHour,
    int? overrideMinute,
    bool clearOverride = false,
    bool clearPreset = false,
  }) {
    return DayPlan(
      date: date,
      presetId: clearPreset ? null : (presetId ?? this.presetId),
      overrideHour: clearOverride ? null : (overrideHour ?? this.overrideHour),
      overrideMinute: clearOverride ? null : (overrideMinute ?? this.overrideMinute),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'presetId': presetId,
        'overrideHour': overrideHour,
        'overrideMinute': overrideMinute,
      };

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        date: j['date'] as String,
        presetId: j['presetId'] as String?,
        overrideHour: j['overrideHour'] as int?,
        overrideMinute: j['overrideMinute'] as int?,
      );
}

/// 特定の日に実際に鳴らすアラームを解決した結果。
class ResolvedAlarm {
  final String dateKey;
  final int hour;
  final int minute;
  final String label;
  final int colorIndex;
  final int snoozeMinutes;
  final bool vibrate;
  final String soundId;
  final bool isOverride;

  const ResolvedAlarm({
    required this.dateKey,
    required this.hour,
    required this.minute,
    required this.label,
    required this.colorIndex,
    required this.snoozeMinutes,
    required this.vibrate,
    required this.soundId,
    required this.isOverride,
  });

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
