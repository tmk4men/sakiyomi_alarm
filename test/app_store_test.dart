import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sakiyomi_alarm/data/app_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppStore> freshStore() async {
    final store = AppStore();
    await store.load();
    return store;
  }

  test('デフォルトで3プリセット（通常/早番/休み）', () async {
    final store = await freshStore();
    expect(store.presets.length, 3);
  });

  test('プリセット割当で resolve が時刻を返す', () async {
    final store = await freshStore();
    final key = dateKeyOf(store.today.add(const Duration(days: 1)));
    await store.assignPreset(key, 'p_early'); // 05:30
    final r = store.resolve(key);
    expect(r, isNotNull);
    expect(r!.hour, 5);
    expect(r.minute, 30);
  });

  test('休みプリセットは resolve=null / dayIsOff=true', () async {
    final store = await freshStore();
    final key = dateKeyOf(store.today.add(const Duration(days: 1)));
    await store.assignPreset(key, 'p_off');
    expect(store.resolve(key), isNull);
    expect(store.dayIsOff(key), true);
  });

  test('この日だけの時刻上書きが優先される', () async {
    final store = await freshStore();
    final key = dateKeyOf(store.today.add(const Duration(days: 2)));
    await store.assignPreset(key, 'p_normal'); // 07:00
    await store.setOverride(key, 4, 15);
    final r = store.resolve(key);
    expect(r!.hour, 4);
    expect(r.minute, 15);
    expect(r.isOverride, true);
  });

  test('無料プランは7日より先をロック', () async {
    final store = await freshStore();
    store.isPro = false;
    final within = dateKeyOf(store.today.add(const Duration(days: 7)));
    final beyond = dateKeyOf(store.today.add(const Duration(days: 8)));
    expect(store.isLocked(within), false);
    expect(store.isLocked(beyond), true);
  });

  test('ロック日への割当はストア層で拒否', () async {
    final store = await freshStore();
    store.isPro = false;
    final beyond = dateKeyOf(store.today.add(const Duration(days: 10)));
    await store.assignPreset(beyond, 'p_normal');
    expect(store.dayPlans.containsKey(beyond), false);
  });

  test('Proならロック日にも割当できる', () async {
    final store = await freshStore();
    store.isPro = true;
    final beyond = dateKeyOf(store.today.add(const Duration(days: 20)));
    await store.assignPreset(beyond, 'p_normal');
    expect(store.dayPlans[beyond]?.presetId, 'p_normal');
  });

  test('くり返し生成で期間が埋まる', () async {
    final store = await freshStore();
    store.isPro = true;
    await store.applyRotation(['p_early', 'p_off'], 4);
    final d0 = dateKeyOf(store.today);
    final d1 = dateKeyOf(store.today.add(const Duration(days: 1)));
    expect(store.dayPlans[d0]?.presetId, 'p_early');
    expect(store.dayPlans[d1]?.presetId, 'p_off');
    expect(store.dayPlans.length >= 4, true);
  });

  test('プリセット削除で使用中の割当も解除', () async {
    final store = await freshStore();
    final key = dateKeyOf(store.today.add(const Duration(days: 1)));
    await store.assignPreset(key, 'p_early');
    await store.deletePreset('p_early');
    expect(store.presets.any((p) => p.id == 'p_early'), false);
    expect(store.dayPlans.containsKey(key), false);
  });
}
