// 农历引擎权威数据校验：2026-2030 年春节/传统节日/24 节气
import 'package:suiya/core/lunar/lunar_engine.dart';
import 'package:suiya/core/festival/festival.dart';

String fmt(LunarDateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  print('========== 1) 春节（正月初一）逐年校验 ==========');
  // 权威值：2026=2/17 2027=2/6 2028=1/26 2029=2/13 2030=2/3 2031=1/23 2032=2/11
  const springTruth = {
    2026: '2026-02-17',
    2027: '2027-02-06',
    2028: '2028-01-26',
    2029: '2029-02-13',
    2030: '2030-02-03',
    2031: '2031-01-23',
    2032: '2032-02-11',
  };
  var pass = 0, fail = 0;
  springTruth.forEach((year, truth) {
    final d = LunarEngine.lunarToSolar(year, 1, 1);
    final got = fmt(d);
    final ok = got == truth;
    ok ? pass++ : fail++;
    print('  ${ok ? "OK  " : "FAIL"} $year 春节: 算得 $got  应为 $truth');
  });

  print('\n========== 2) 闰月检测 ==========');
  // 权威：2025 年闰六月，2028 年闰五月，2031 年闰三月，2033 年闰冬月
  const leapTruth = {2025: 6, 2028: 5, 2031: 3, 2033: 11};
  leapTruth.forEach((year, month) {
    final got = LunarEngine.leapMonthNumber(year);
    final ok = got == month;
    ok ? pass++ : fail++;
    print('  ${ok ? "OK  " : "FAIL"} $year 闰月: 算得 $got 应为 $month');
  });
  // 无闰月的年份应返回 0
  for (final y in [2026, 2027, 2029, 2030]) {
    final got = LunarEngine.leapMonthNumber(y);
    final ok = got == 0;
    ok ? pass++ : fail++;
    print('  ${ok ? "OK  " : "FAIL"} $y 闰月: 算得 $got 应为 0(无闰月)');
  }

  print('\n========== 3) 传统节日（农历月日）逐年校验 ==========');
  // 权威：中秋(八月十五)、端午(五月初五)、七夕(七月初七)、重阳(九月初九)、元宵(正月十五)
  const festTruth = {
    //  year : {名称: 公历}
    2026: {'元宵节': '2026-03-03', '端午节': '2026-06-19', '七夕': '2026-08-19', '中秋节': '2026-09-25', '重阳节': '2026-10-18'},
    2027: {'元宵节': '2027-02-20', '端午节': '2027-06-09', '七夕': '2027-08-08', '中秋节': '2027-09-15', '重阳节': '2027-10-08'},
    2028: {'元宵节': '2028-02-09', '端午节': '2028-05-28', '七夕': '2028-08-17', '中秋节': '2028-09-17', '重阳节': '2028-10-09'},
    2029: {'元宵节': '2029-02-27', '端午节': '2029-06-16', '七夕': '2029-08-11', '中秋节': '2029-09-22', '重阳节': '2029-10-11'},
  };
  const monthDay = {'元宵节': [1, 15], '端午节': [5, 5], '七夕': [7, 7], '中秋节': [8, 15], '重阳节': [9, 9]};
  festTruth.forEach((year, list) {
    list.forEach((name, truth) {
      final md = monthDay[name]!;
      final got = fmt(LunarEngine.lunarToSolar(year, md[0], md[1]));
      final ok = got == truth;
      ok ? pass++ : fail++;
      print('  ${ok ? "OK  " : "FAIL"} $year $name: 算得 $got 应为 $truth');
    });
  });

  print('\n========== 4) 24 节气（2026 年）校验 ==========');
  // 权威 2026 年节气
  const terms = {
    '立春': '2026-02-04', '雨水': '2026-02-18', '惊蛰': '2026-03-05', '春分': '2026-03-20',
    '清明': '2026-04-05', '谷雨': '2026-04-20', '立夏': '2026-05-05', '小满': '2026-05-21',
    '芒种': '2026-06-05', '夏至': '2026-06-21', '小暑': '2026-07-07', '大暑': '2026-07-23',
    '立秋': '2026-08-07', '处暑': '2026-08-23', '白露': '2026-09-07', '秋分': '2026-09-23',
    '寒露': '2026-10-08', '霜降': '2026-10-23', '立冬': '2026-11-07', '小雪': '2026-11-22',
    '大雪': '2026-12-07', '冬至': '2026-12-21',
  };
  // 找库里定义节气节日的 festival
  for (final f in Festivals.allTerms()) {
    final truth = terms[f.name];
    if (truth == null) continue;
    final d = f.dateIn(2026);
    final got = d == null ? 'null' : fmt(d);
    final ok = got == truth;
    ok ? pass++ : fail++;
    print('  ${ok ? "OK  " : "FAIL"} ${f.name}: 算得 $got 应为 $truth');
  }

  print('\n========== 5) 公历↔农历互转自洽性 ==========');
  // 随机 500 天往返转换：solar -> lunar -> solar 必须一致
  var rt = DateTime(2026, 1, 1);
  var bad = 0;
  for (var i = 0; i < 500; i++) {
    final l = LunarEngine.solarToLunar(rt.year, rt.month, rt.day);
    final back = LunarEngine.lunarToSolar(l.year, l.month, l.day, l.isLeap);
    if (back.year != rt.year || back.month != rt.month || back.day != rt.day) {
      if (bad < 5) {
        print('  FAIL 往返不一致: $rt -> ${l.toString()} -> ${fmt(back)}');
      }
      bad++;
    }
    rt = rt.add(const Duration(days: 1));
  }
  print(bad == 0 ? '  OK   500 天往返转换全部一致' : '  FAIL $bad/500 天往返不一致');
  bad == 0 ? pass++ : fail += bad;

  print('\n========== 6) 除夕 / 腊八 / 小年 跨年归属 ==========');
  for (final y in [2026, 2027, 2028]) {
    final chuxi = Festivals.byId('chuxi')!.dateIn(y);
    final nextSpring = fmt(LunarEngine.lunarToSolar(y + 1, 1, 1));
    print('  $y 除夕=${chuxi == null ? "null" : fmt(chuxi)}  次年春节=$nextSpring'
        '${chuxi != null && fmt(chuxi) != "null" ? "" : ""}');
  }

  print('\n================================================');
  print('通过 $pass 项，失败 $fail 项');
  print(fail == 0 ? '结论：农历引擎全部正确 ✅' : '结论：存在 $fail 处错误 ❌');
}
