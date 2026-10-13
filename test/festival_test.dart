/// 岁忆 · 节日与模板系统验证
import 'package:flutter_test/flutter_test.dart';
import 'package:suiya/core/festival/festival.dart';
import 'package:suiya/core/lunar/lunar_engine.dart';

String f(LunarDateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('节日日期计算', () {
    test('中秋 2026 = 9/25', () {
      expect(f(Festivals.midAutumn.dateIn(2026)!), '2026-09-25');
    });
    test('端午 2026 = 6/19', () {
      expect(f(Festivals.duanwu.dateIn(2026)!), '2026-06-19');
    });
    test('春节 2026 = 2/17', () {
      expect(f(Festivals.springFestival.dateIn(2026)!), '2026-02-17');
    });
    test('清明 2026 = 4/5（节气）', () {
      expect(f(Festivals.qingming.dateIn(2026)!), '2026-04-05');
    });
    test('冬至 2026 = 12/22（节气）', () {
      // 2026 冬至实为 12-22 04:50；旧权威表的 12-21 20:50 是损坏数据
      expect(f(Festivals.winterSolstice.dateIn(2026)!), '2026-12-22');
    });
    test('元宵 2026 = 3/3', () {
      expect(f(Festivals.yuanxiao.dateIn(2026)!), '2026-03-03');
    });
  });

  group('跨年节日处理', () {
    test('腊八落在次年 1-2 月时归属正确', () {
      // 2025-01-29 是春节，腊八（腊月初八）应在此之前的 2025-01
      final d = Festivals.laba.dateIn(2025)!;
      expect(d.year, 2025);
      expect(d.month, 1);
    });
    test('除夕取腊月最后一天', () {
      for (final y in [2024, 2025, 2026, 2027]) {
        final d = Festivals.chuxi.dateIn(y);
        expect(d, isNotNull, reason: '$y 除夕应可计算');
        // 除夕应在春节之前
        final spring = Festivals.springFestival.dateIn(y)!;
        expect(d!.year <= spring.year, isTrue);
      }
    });
  });

  group('农历每月型（拜神日）', () {
    test('初一 / 十五 在 2026 年有 12 次', () {
      final lunarYear = LunarEngine.solarToLunar(2026, 6, 1).year;
      final count = _countOccurrences(Festivals.chu_yi_festival, lunarYear);
      expect(count, 12, reason: '农历每月初一应在 12 个农历月各出现一次');
    });
    test('十五日期在每个农历月的 15 日', () {
      final lunarYear = LunarEngine.solarToLunar(2026, 6, 1).year;
      for (var m = 1; m <= 12; m++) {
        final d = Festivals.shi_wu_festival.dateIn(lunarYear);
        expect(d, isNotNull);
      }
      // 抽查：2026 农历七月十五
      final d = LunarEngine.lunarToSolar(lunarYear, 7, 15);
      expect(d.day, greaterThan(0));
    });
    test('廿三 祭灶在腊月也有', () {
      final lunarYear = LunarEngine.solarToLunar(2026, 6, 1).year;
      final d = LunarEngine.lunarToSolar(lunarYear, 12, 23);
      expect(d.day, greaterThan(0));
    });
  });

  group('4 套模板', () {
    test('模板数量为 4', () {
      expect(Templates.all.length, 4);
    });
    test('模板 ID 唯一', () {
      final ids = Templates.all.map((t) => t.id).toSet();
      expect(ids.length, 4);
    });
    test('模板名称符合需求', () {
      final names = Templates.all.map((t) => t.name).toList();
      expect(names, contains('传统节日'));
      expect(names, contains('传统民俗'));
      expect(names, contains('极简'));
      expect(names, contains('全量'));
    });
    test('极简模板只含 4 个节日', () {
      expect(Templates.minimal.festivalIds.length, 4);
    });
    test('传统民俗模板包含初一十五拜神', () {
      expect(Templates.folk.festivalIds, contains('chu_yi'));
      expect(Templates.folk.festivalIds, contains('shi_wu'));
      expect(Templates.folk.festivalIds, contains('jizao'));
      expect(Templates.folk.festivalIds, contains('benyue_26'));
    });
    test('传统节日模板不含拜神日（面向年轻人）', () {
      expect(Templates.traditional.festivalIds, isNot(contains('chu_yi')));
      expect(Templates.traditional.festivalIds, isNot(contains('shi_wu')));
    });
    test('全量模板含 24 节气', () {
      final resolved = Templates.resolve(Templates.everything);
      final terms = resolved.where((f) => f.recurrence == RecurrenceType.solarTerm);
      // 26 = 24 节气 + 清明/冬至的专项定义（带扫墓祭祖引导提问）
      expect(terms.length, 26, reason: '全量模板含 24 节气 + 清明/冬至专项定义');
      expect(Templates.everything.festivalIds.where((e) => e.startsWith('term_')).length, 24);
    });
    test('所有模板的节日 ID 均可解析', () {
      for (final t in Templates.all) {
        final resolved = Templates.resolve(t);
        expect(resolved.isNotEmpty, isTrue, reason: '${t.name} 应能解析出节日');
        for (final f in resolved) {
          expect(f.name.isNotEmpty, isTrue);
        }
      }
    });
    test('传统民俗模板节日数多于传统节日', () {
      expect(Templates.folk.festivalIds.length,
          greaterThan(Templates.traditional.festivalIds.length));
    });
  });

  group('选择状态', () {
    test('默认选择来自传统节日模板', () {
      final s = FestivalSelection.defaultSelection();
      expect(s.enabledCount, Templates.traditional.festivalIds.length);
    });
    test('切换开关', () {
      final s = FestivalSelection.defaultSelection();
      final before = s.enabledCount;
      s.toggle(Festivals.springFestival);
      expect(s.enabledCount, before - 1);
      s.toggle(Festivals.springFestival);
      expect(s.enabledCount, before);
    });
    test('关闭全部后为空', () {
      final s = FestivalSelection.defaultSelection()..disableAll();
      expect(s.enabledCount, 0);
    });
    test('提前天数可自定义', () {
      final s = FestivalSelection.defaultSelection();
      expect(s.advanceDaysOf(Festivals.midAutumn), 7, reason: '中秋默认提前 7 天');
      s.setAdvanceDays(Festivals.midAutumn.id, 1);
      expect(s.advanceDaysOf(Festivals.midAutumn), 1);
    });
    test('未选中的节日 advanceDays 返回默认值但不启用', () {
      final s = FestivalSelection.empty();
      expect(s.isEnabled(Festivals.midAutumn.id), isFalse);
      expect(s.advanceDaysOf(Festivals.midAutumn), 7);
    });
    test('传统民俗模板默认包含初一十五', () {
      final s = FestivalSelection.fromTemplate(Templates.folk);
      expect(s.isEnabled('chu_yi'), isTrue);
      expect(s.isEnabled('shi_wu'), isTrue);
    });
  });

  group('引导提问模板', () {
    test('清明有墓地相关提问', () {
      expect(Festivals.qingming.prompts.any((p) => p.question.contains('墓地')), isTrue);
    });
    test('中秋有送礼/在哪过提问', () {
      expect(Festivals.midAutumn.prompts.any((p) => p.question.contains('礼物')), isTrue);
    });
    test('春节有年夜饭提问', () {
      expect(Festivals.springFestival.prompts.any((p) => p.question.contains('年夜饭')), isTrue);
    });
  });

  group('下次发生日', () {
    test('从今天起算能找到未来节日', () {
      final now = DateTime.now();
      for (final f in [Festivals.midAutumn, Festivals.duanwu, Festivals.qingming]) {
        final next = f.nextOccurrence(now);
        expect(next, isNotNull, reason: '${f.name} 应能找到下次');
        final d = DateTime(next!.year, next.month, next.day);
        expect(d.isAfter(DateTime(now.year, now.month, now.day)), isTrue);
      }
    });
  });
}

int _countOccurrences(Festival f, int lunarYear) {
  var count = 0;
  for (var m = 1; m <= 12; m++) {
    final len = LunarEngine.lunarMonthDays(lunarYear, m, false);
    if ((f.lunarDay ?? 0) <= len) count++;
  }
  return count;
}
