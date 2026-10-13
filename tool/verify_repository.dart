// 记录仓储单元测试：不需要 Flutter 引擎，`dart run` 直接跑
import 'package:suiya/features/record/domain/inmemory_repository.dart';
import 'package:suiya/features/record/domain/memory_codec.dart';
import 'package:suiya/core/lunar/lunar_engine.dart';
import 'package:suiya/features/record/domain/memory_record.dart';

int pass = 0, fail = 0;

void check(String label, bool ok, [String? detail]) {
  if (ok) {
    pass++;
    print('  OK   $label');
  } else {
    fail++;
    print('  FAIL $label${detail == null ? '' : ' — $detail'}');
  }
}

/// 测试解析器：让 qixi 落在 3 天后，mid_autumn 落在 30 天后
/// 返回 LunarDateTime（字段即公历年月日）
LunarDateTime _fakeResolve(String festivalId, int year) {
  final now = DateTime.now();
  if (festivalId == 'qixi') {
    final d = DateTime(now.year, now.month, now.day).add(const Duration(days: 3));
    return LunarDateTime(d.year, d.month, d.day);
  }
  if (festivalId == 'mid_autumn') {
    final d = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));
    return LunarDateTime(d.year, d.month, d.day);
  }
  return LunarDateTime(year, 8, 19);
}

Future<void> main() async {
  // 模拟 presentation 层启动时注入解析器
  MemoryRecord.bindFestivalResolver(_fakeResolve);
  final repo = InMemoryMemoryRepository();
  await repo.init();
  final year = DateTime.now().year;

  print('=== 1) 保存与读取 ===');
  final now = DateTime.now().millisecondsSinceEpoch;
  final rec = MemoryRecord(
    id: 'r1',
    festivalId: 'mid_autumn',
    year: year,
    title: '$year年中秋·回家',
    text: '院子里的桂花开得很盛',
    qa: const [QaItem('今年在哪家过？', '自己家')],
    participants: const ['爸妈', '小妹'],
    tags: const ['团圆', '桂花'],
    createdAt: now,
    updatedAt: now,
  );
  await repo.save(rec);
  check('按 id 读到', (await repo.byId('r1'))?.title == rec.title);
  check('按节日+年份读到', (await repo.find('mid_autumn', year))?.id == 'r1');
  check('按年份查询命中', (await repo.byYear(year)).length == 1);
  check('别的年份查不到', (await repo.find('mid_autumn', year + 1)) == null);

  print('\n=== 2) 同节日不同年份是两条独立记录 ===');
  await repo.save(MemoryRecord(
    id: 'r2',
    festivalId: 'mid_autumn',
    year: year + 1,
    title: '${
        year + 1}年中秋',
    createdAt: now,
    updatedAt: now,
  ));
  check('今年那条未被覆盖', (await repo.find('mid_autumn', year))?.id == 'r1');
  check('次年那条独立存在', (await repo.find('mid_autumn', year + 1))?.id == 'r2');
  check('全部记录 2 条', (await repo.all()).length == 2);

  print('\n=== 3) 更新 ===');
  await repo.save(rec.copyWith(title: '改过的标题', updatedAt: now + 1));
  check('标题已更新',
      (await repo.byId('r1'))?.title == '改过的标题');
  check('正文未丢失', (await repo.byId('r1'))?.text == rec.text);
  check('问答未丢失', (await repo.byId('r1'))?.qa.length == 1);
  check('参与人未丢失', (await repo.byId('r1'))?.participants.length == 2);

  print('\n=== 4) 提醒筛选 ===');
  final soon = DateTime.now().add(const Duration(days: 3));
  await repo.save(MemoryRecord(
    id: 'r3',
    festivalId: 'qixi',
    year: year,
    title: '七夕',
    remindOn: true,
    createdAt: now,
    updatedAt: now,
  ));
  final rem = await repo.upcomingReminders(withinDays: 30);
  check('3 天内提醒只 1 条', rem.length == 1, '实际 ${rem.length}');
  check('提醒是 qixi', rem.first.festivalId == 'qixi');

  print('\n=== 5) 删除 ===');
  await repo.delete('r3');
  check('删除后不在', (await repo.byId('r3')) == null);
  check('删除后无提醒', (await repo.upcomingReminders(withinDays: 30)).isEmpty);
  check('其他记录仍在', (await repo.byId('r1')) != null);

  print('\n=== 6) 序列化往返（模拟 DB 存取） ===');
  final original = MemoryRecord(
    id: 'r4',
    year: year,
    title: '序列化测试',
    text: '正文',
    qa: const [QaItem('问题一？', '答案一'), QaItem('问题二？', '答案二')],
    participants: const ['甲', '乙'],
    tags: const ['x', 'y'],
    lat: 23.1291,
    lng: 113.2644,
    syncPolicy: SyncPolicy.always,
    createdAt: now,
    updatedAt: now,
  );
  // 走 sqflite 实现里的静态编解码
  final qaJson = MemoryCodec.dumpQa(original.qa);
  final back = MemoryCodec.parseQa(qaJson);
  check('问答往返一致', back.length == 2 && back[1].answer == '答案二');
  check('参与者 JSON 正常', MemoryCodec.splitList('["甲","乙"]').length == 2);
  check('脏 JSON 不崩',
      MemoryCodec.splitList('not json').isEmpty);
  check('经纬度保留', original.lat == 23.1291 && original.lng == 113.2644);
  check('syncPolicy 保留', original.syncPolicy == SyncPolicy.always);

  print('\n================================================');
  print('通过 $pass 项，失败 $fail 项');
  if (fail > 0) throw StateError('有 $fail 项失败');
}
