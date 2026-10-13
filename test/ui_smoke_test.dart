import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:suiya/app/router.dart';
import 'package:suiya/core/festival/festival.dart';
import 'package:suiya/core/storage.dart';
import 'package:suiya/core/theme.dart';
import 'package:suiya/features/record/domain/inmemory_repository.dart';
import 'package:suiya/features/record/domain/memory_record.dart';
import 'package:suiya/features/record/presentation/record_providers.dart';

void main() {
  setUpAll(() {
    MemoryRecord.bindFestivalResolver((id, y) => Festivals.byId(id)?.dateIn(y));
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('T1 首页渲染无异常', (tester) async {
    final st = await SuiyaStorage.open();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(st),
        memoryRepositoryProvider.overrideWithValue(InMemoryMemoryRepository()),
      ],
      child: MaterialApp.router(
        theme: SuiyaTheme.light(),
        routerConfig: appRouter,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final n = find.byType(Text).evaluate().length;
    final err = tester.takeException();
    // ignore: avoid_print
    print('>>> T1 TextCount=$n Exception=$err');
    expect(err, isNull);
    expect(n, greaterThan(0));
  });

  test('T2 同节日跨年份是两条独立记录', () {
    final repo = InMemoryMemoryRepository();
    final now = DateTime.now().millisecondsSinceEpoch;
    repo.syncSave(MemoryRecord(
        id: 'a', festivalId: 'qixi', year: 2026,
        title: '2026七夕', createdAt: now, updatedAt: now));
    repo.syncSave(MemoryRecord(
        id: 'b', festivalId: 'qixi', year: 2027,
        title: '2027七夕', createdAt: now, updatedAt: now));
    // ignore: avoid_print
    print('>>> T2 2026=${repo.syncFind('qixi', 2026)?.title} 2027=${repo.syncFind('qixi', 2027)?.title}');
    expect(repo.syncFind('qixi', 2026)?.title, '2026七夕');
    expect(repo.syncFind('qixi', 2027)?.title, '2027七夕');
  });

  test('T3 节日日期解析正确', () {
    final r = MemoryRecord(
        id: 'x', festivalId: 'mid_autumn', year: 2026,
        title: 't', createdAt: 0, updatedAt: 0);
    // ignore: avoid_print
    print('>>> T3 中秋2026=${r.date}');
    expect(r.date!.month, 9);
    expect(r.date!.day, 25);
  });
}
