/// 岁忆 · 农历引擎 Dart 版验证
///
/// 对标 Node 版已验证的期望值，确保转译正确。
/// 运行：flutter test test/lunar_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:suiya/core/lunar/lunar_engine.dart';

String f(LunarDateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('春节（农历正月初一）', () {
    const data = {
      2020: '2020-01-25', 2021: '2021-02-12', 2022: '2022-02-01',
      2023: '2023-01-22', 2024: '2024-02-10', 2025: '2025-01-29',
      2026: '2026-02-17', 2027: '2027-02-06', 2028: '2028-01-26',
      2029: '2029-02-13', 2030: '2030-02-03', 2031: '2031-01-23',
      2032: '2032-02-11', 2033: '2033-01-31',
    };
    data.forEach((y, exp) {
      test('$y 春节', () {
        expect(f(LunarEngine.lunarToSolar(y, 1, 1)), exp);
      });
    });
  });

  group('中秋节（八月十五）', () {
    const data = {
      2020: '2020-10-01', 2021: '2021-09-21', 2022: '2022-09-10',
      2023: '2023-09-29', 2024: '2024-09-17', 2025: '2025-10-06',
      2026: '2026-09-25', 2027: '2027-09-15', 2028: '2028-10-03',
    };
    data.forEach((y, exp) {
      test('$y 中秋', () => expect(f(LunarEngine.lunarToSolar(y, 8, 15)), exp));
    });
  });

  group('端午节（五月初五）', () {
    const data = {
      2020: '2020-06-25', 2021: '2021-06-14', 2022: '2022-06-03',
      2023: '2023-06-22', 2024: '2024-06-10', 2025: '2025-05-31',
      2026: '2026-06-19', 2027: '2027-06-09', 2028: '2028-05-28',
    };
    data.forEach((y, exp) {
      test('$y 端午', () => expect(f(LunarEngine.lunarToSolar(y, 5, 5)), exp));
    });
  });

  group('元宵（正月十五）', () {
    const data = {
      2024: '2024-02-24', 2025: '2025-02-12', 2026: '2026-03-03',
      2027: '2027-02-20', 2028: '2028-02-09',
    };
    data.forEach((y, exp) {
      test('$y 元宵', () => expect(f(LunarEngine.lunarToSolar(y, 1, 15)), exp));
    });
  });

  group('七夕（七月初七）', () {
    const data = {
      2024: '2024-08-10', 2025: '2025-08-29', 2026: '2026-08-19',
      2027: '2027-08-08', 2028: '2028-08-26',
    };
    data.forEach((y, exp) {
      test('$y 七夕', () => expect(f(LunarEngine.lunarToSolar(y, 7, 7)), exp));
    });
  });

  group('重阳（九月初九）', () {
    const data = {
      2024: '2024-10-11', 2025: '2025-10-29', 2026: '2026-10-18',
      2027: '2027-10-08', 2028: '2028-10-26',
    };
    data.forEach((y, exp) {
      test('$y 重阳', () => expect(f(LunarEngine.lunarToSolar(y, 9, 9)), exp));
    });
  });

  group('除夕（腊月最后一天）', () {
    const data = {
      2023: '2023-01-21', 2024: '2024-02-09', 2025: '2025-01-28',
      2026: '2026-02-16', 2027: '2027-02-05',
    };
    data.forEach((y, exp) {
      test('$y 除夕', () => expect(f(LunarEngine.lunarNewYearEve(y - 1)), exp));
    });
  });

  group('二十四节气', () {
    test('清明', () {
      expect(f(LunarEngine.termDate(2024, 15)), '2024-04-04');
      expect(f(LunarEngine.termDate(2026, 15)), '2026-04-05');
    });
    test('冬至', () {
      expect(f(LunarEngine.termDate(2024, 270)), '2024-12-21');
      // 2026 冬至实为 12-22 04:50（旧权威表写 12-21 20:50 是损坏数据）
      expect(f(LunarEngine.termDate(2026, 270)), '2026-12-22');
    });
    test('权威表损坏条目的回归（已删去，由天文兜底计算）', () {
      // 2022 芒种实为 06-06 00:25（旧表 06-05 23:17 错一天）
      expect(f(LunarEngine.termDate(2022, 75)), '2022-06-06');
      // 2022 白露实为 09-07 23:32（旧表 09-08 00:06 错一天）
      expect(f(LunarEngine.termDate(2022, 165)), '2022-09-07');
      // 2027 立冬实为 11-07 23:38（旧表 11-08 01:33 错一天）
      expect(f(LunarEngine.termDate(2027, 225)), '2027-11-07');
    });
    test('立春', () {
      expect(f(LunarEngine.termDate(2026, 315)), '2026-02-04');
    });
    test('夏至', () {
      expect(f(LunarEngine.termDate(2026, 90)), '2026-06-21');
    });
    test('节气名称映射', () {
      expect(LunarEngine.termName(315), '立春');
      expect(LunarEngine.termName(15), '清明');
      expect(LunarEngine.termName(270), '冬至');
      expect(LunarEngine.termName(90), '夏至');
    });
    test('节气时刻精确到分钟', () {
      // 2020 春分 = 11:49:29（北京）
      final d = LunarEngine.termDate(2020, 0);
      expect(f(d), '2020-03-20');
      expect(d.hour, 11);
      expect(d.minute, 49);
    });
  });

  group('小寒/大寒（走天文兜底路径）', () {
    // 权威表不含 285/300，这两个节气全部由天文算法计算，
    // 是兜底路径坐标系的回归测试（旧算法偏早约 4 小时，凌晨节气会错一天）。
    const xiaohan = {
      2020: '2020-01-06', 2021: '2021-01-05', 2022: '2022-01-05',
      2023: '2023-01-05', 2024: '2024-01-06', 2025: '2025-01-05',
      2026: '2026-01-05',
    };
    const dahan = {
      2020: '2020-01-20', 2021: '2021-01-20', 2022: '2022-01-20',
      2023: '2023-01-20', 2024: '2024-01-20', 2025: '2025-01-20',
      2026: '2026-01-20',
    };
    xiaohan.forEach((y, exp) {
      test('$y 小寒', () => expect(f(LunarEngine.termDate(y, 285)), exp));
    });
    dahan.forEach((y, exp) {
      test('$y 大寒', () => expect(f(LunarEngine.termDate(y, 300)), exp));
    });
  });

  group('农历日号越界钳制', () {
    test('小月求「三十」应得到廿九，而不是下月初一', () {
      for (var y = 2020; y <= 2030; y++) {
        for (var m = 1; m <= 12; m++) {
          final len = LunarEngine.lunarMonthDays(y, m, false);
          final d30 = LunarEngine.lunarToSolar(y, m, 30);
          final expected = LunarEngine.lunarToSolar(y, m, len);
          expect(f(d30), f(expected),
              reason: '$y 农历 $m 月仅 $len 天，三十应钳制到月末');
        }
      }
    });
    test('该年无闰月时回退到同名平月', () {
      // 2026 无闰月
      expect(
          f(LunarEngine.lunarToSolar(2026, 6, 1, true)),
          f(LunarEngine.lunarToSolar(2026, 6, 1, false)));
    });
  });

  group('闰月', () {
    test('已知闰月年份', () {
      const data = {
        2020: 4, 2023: 2, 2025: 6, 2028: 5, 2031: 3, 2033: 11,
        2001: 4, 2004: 2, 2006: 7, 2012: 4, 2014: 9, 2017: 6,
      };
      data.forEach((y, exp) {
        expect(LunarEngine.leapMonthNumber(y), exp, reason: '$y 闰月');
      });
    });
    test('无闰月年份', () {
      for (final y in [2026, 2027, 2029, 2030, 2000, 2010, 1920, 1950]) {
        expect(LunarEngine.leapMonthNumber(y), 0, reason: '$y 应无闰月');
      }
    });
    test('2025 闰六月初一', () {
      // 2025 闰六月：普通六月 2025-06-25，闰六月 2025-07-25
      expect(f(LunarEngine.lunarToSolar(2025, 6, 1, false)), '2025-06-25');
      expect(f(LunarEngine.lunarToSolar(2025, 6, 1, true)), '2025-07-25');
    });
  });

  group('公历转农历', () {
    test('抽样验证', () {
      expect(f(LunarEngine.solarToLunar(2026, 2, 17).toSolar()), '2026-02-17');
      expect(LunarEngine.solarToLunar(2026, 6, 19).month, 5);
      expect(LunarEngine.solarToLunar(2026, 9, 25).month, 8);
      // 2025-07-25 是闰六月初一
      final l = LunarEngine.solarToLunar(2025, 7, 25);
      expect(l.month, 6);
      expect(l.isLeap, isTrue);
    });
  });

  group('往返一致性', () {
    test('2026 全年逐日', () {
      for (var m = 1; m <= 12; m++) {
        // 2026 非闰年，用 DateTime 正确取每月天数
        final dim = DateTime(2026, m + 1, 0).day;
        for (var d = 1; d <= dim; d++) {
          final l = LunarEngine.solarToLunar(2026, m, d);
          final back = l.toSolar();
          final expected = '2026-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
          expect(f(back), expected, reason: '$expected 往返失败（$l）');
        }
      }
    });
  });

  group('月长与年长', () {
    test('农历年天数在 353-385 之间', () {
      for (var y = 2020; y <= 2030; y++) {
        final days = LunarEngine.lunarYearDays(y);
        expect(days, greaterThanOrEqualTo(353));
        expect(days, lessThanOrEqualTo(385));
      }
    });
    test('月长为 29 或 30', () {
      for (var y = 2026; y <= 2027; y++) {
        for (var m = 1; m <= 12; m++) {
          final d = LunarEngine.lunarMonthDays(y, m, false);
          expect(d == 29 || d == 30, isTrue, reason: '$y 年 $m 月天数异常: $d');
        }
      }
    });
  });
}
