import 'package:flutter_test/flutter_test.dart';

import 'package:sakiyomi_alarm/models/preset.dart';

void main() {
  test('Preset の休み判定と時刻ラベル', () {
    const off = Preset(id: 'a', name: '休み', hour: null, minute: null);
    expect(off.isDayOff, true);
    expect(off.timeLabel, '休み');

    const early = Preset(id: 'b', name: '早番', hour: 5, minute: 30);
    expect(early.isDayOff, false);
    expect(early.timeLabel, '05:30');
  });

  test('Preset の JSON 往復', () {
    const p = Preset(id: 'c', name: '通常', hour: 7, minute: 0, colorIndex: 2);
    final restored = Preset.fromJson(p.toJson());
    expect(restored.id, p.id);
    expect(restored.name, p.name);
    expect(restored.hour, 7);
    expect(restored.colorIndex, 2);
  });
}
