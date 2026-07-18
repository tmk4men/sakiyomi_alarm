/// よく使う起床パターン。ユーザーが自由に登録・編集する。
/// [hour]/[minute] が null の場合は「休み（アラームなし）」。
class Preset {
  final String id;
  final String name;
  final int? hour;
  final int? minute;
  final int colorIndex;
  final String soundId;
  final int snoozeMinutes;
  final bool vibrate;

  const Preset({
    required this.id,
    required this.name,
    this.hour,
    this.minute,
    this.colorIndex = 0,
    this.soundId = 'default',
    this.snoozeMinutes = 5,
    this.vibrate = true,
  });

  bool get isDayOff => hour == null || minute == null;

  String get timeLabel {
    if (isDayOff) return '休み';
    return '${hour!.toString().padLeft(2, '0')}:${minute!.toString().padLeft(2, '0')}';
  }

  Preset copyWith({
    String? name,
    int? colorIndex,
    String? soundId,
    int? snoozeMinutes,
    bool? vibrate,
    int? hour,
    int? minute,
    bool? dayOff,
  }) {
    final off = dayOff ?? isDayOff;
    return Preset(
      id: id,
      name: name ?? this.name,
      hour: off ? null : (hour ?? this.hour),
      minute: off ? null : (minute ?? this.minute),
      colorIndex: colorIndex ?? this.colorIndex,
      soundId: soundId ?? this.soundId,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      vibrate: vibrate ?? this.vibrate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hour': hour,
        'minute': minute,
        'colorIndex': colorIndex,
        'soundId': soundId,
        'snoozeMinutes': snoozeMinutes,
        'vibrate': vibrate,
      };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
        id: j['id'] as String,
        name: j['name'] as String,
        hour: j['hour'] as int?,
        minute: j['minute'] as int?,
        colorIndex: (j['colorIndex'] as int?) ?? 0,
        soundId: (j['soundId'] as String?) ?? 'default',
        snoozeMinutes: (j['snoozeMinutes'] as int?) ?? 5,
        vibrate: (j['vibrate'] as bool?) ?? true,
      );
}
