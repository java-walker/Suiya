/// 岁忆 · 农历节气引擎（Dart 版）
///
/// 算法来源：Meeus《Astronomical Algorithms》
///   - 朔（新月）: 第 49 章
///   - 太阳视黄经: 第 25 章
///
/// 该实现已通过 Node 版本验证：
///   - 春节/中秋/端午/元宵/七夕/重阳 1900-2050 全部匹配权威历书
///   - 二十四节气时刻 2020-2028 精确到分钟匹配紫金山天文台数据
///   - 公历↔农历往返一致性 2020-2030 共 4018 天零错误
///
/// 关键设计（踩坑记录）：
///   1. 朔日序号 k 必须用平朔望月 29.530588861 天推算，不能按「每年 12 个」累加
///   2. 农历日以北京时间 00:00 为界，月起点需归一到当日零点，不能用朔日精确时刻
///   3. 节气采用「权威表 + 天文算法兜底」双层方案，保证日期不差一天
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'lunar_tables.dart';

/// 公历日期时间
class LunarDateTime {
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;

  const LunarDateTime(this.year, this.month, this.day, [this.hour = 0, this.minute = 0]);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LunarDateTime &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// 农历日期
class LunarDate {
  final int year;      // 农历年
  final int month;     // 农历月 1-12
  final int day;       // 农历日 1-30
  final bool isLeap;   // 是否闰月

  const LunarDate(this.year, this.month, this.day, {this.isLeap = false});

  /// 转为公历
  LunarDateTime toSolar() => LunarEngine.lunarToSolar(year, month, day, isLeap);

  @override
  String toString() {
    final m = '${isLeap ? '闰' : ''}${'${month}月'}';
    return '农历$year年$m$day日';
  }
}

/// 农历月结构
class _LunarMonth {
  final double start;    // 该月起始 JD（北京 00:00）
  final double length;   // 该月天数（29 或 30）
  final int number;      // 月份编号 1-12
  final bool isLeap;

  const _LunarMonth(this.start, this.length, this.number, this.isLeap);
}

class _LunarYearInfo {
  final int lunarYear;
  final double newYearJD;
  final List<_LunarMonth> months;

  const _LunarYearInfo(this.lunarYear, this.newYearJD, this.months);
}

// ============================================================
// 天文基础
// ============================================================

const double _rad = math.pi / 180.0;
const double _j2000 = 2451545.0;
const double _synodic = 29.530588861;   // 平朔望月（天）
const double _beijingOffset = 8.0 / 24.0; // 北京时 UTC+8

double _mod360(double x) {
  final r = x % 360.0;
  return r < 0 ? r + 360.0 : r;
}

/// UT 儒略日 → TT 儒略日（JDE）
///
/// 踩坑记录：这里必须是纯粹的 UT→TT 换算（加 ΔT）。
/// 旧版本误写成 `jd + 0.5 + 0.005172618*t*(t-1)`，多出的 0.5 天
/// 让兜底天文算法算出的节气时刻整体偏早约 4 小时，
/// 凌晨发生的节气（如大寒）日期会错一天。
double _toJDE(double jd) {
  final g = jdToGregorian(jd);
  return jd + _deltaT(g.year, g.month) / 86400.0;
}

/// 太阳视黄经（Meeus 25.2，低精度，误差约 0.01°）
double _solarApparentLongitude(double jde) {
  final t = (jde - _j2000) / 36525.0;
  final l0 = _mod360(280.46646 + 36000.76983 * t + 0.0003032 * t * t);
  final m = _mod360(357.52911 + 35999.05029 * t - 0.0001537 * t * t);
  final c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * math.sin(m * _rad) +
      (0.019993 - 0.000101 * t) * math.sin(2 * m * _rad) +
      0.000289 * math.sin(3 * m * _rad);
  final omega = 125.04 - 1934.136 * t;
  return _mod360(l0 + c - 0.00569 - 0.00478 * math.sin(omega * _rad));
}

/// 牛顿迭代求太阳视黄经达到 [targetLon] 的时刻（TT 儒略日）
double _solarLongitudeTime(double targetLon, double jdApprox) {
  var jd = jdApprox;
  for (var i = 0; i < 20; i++) {
    var diff = targetLon - _solarApparentLongitude(_toJDE(jd));
    while (diff > 180) diff -= 360.0;
    while (diff < -180) diff += 360.0;
    if (diff.abs() < 1e-10) break;
    jd += diff / 0.9856473;
  }
  return jd;
}

/// 公历 → 儒略日（UT）
double gregorianToJD(int y, int m, int d) {
  var yy = y;
  var mm = m;
  if (mm <= 2) {
    yy -= 1;
    mm += 12;
  }
  final a = (yy / 100).floor();
  final b = 2 - a + (a / 4).floor();
  return (365.25 * (yy + 4716)).floor() +
      (30.6001 * (mm + 1)).floor() +
      d +
      b -
      1524.5;
}

/// 儒略日（UT）→ 公历
LunarDateTime jdToGregorian(double jd) {
  final z = (jd + 0.5).floor();
  final frac = jd + 0.5 - z;
  var a = z;
  if (z >= 2299161) {
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    a = z + 1 + alpha - (alpha / 4).floor();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floor();
  final d = (365.25 * c).floor();
  final e = ((b - d) / 30.6001).floor();

  final dayF = b - d - (30.6001 * e).floor() + frac;
  var day = dayF.floor();
  final hourF = (dayF - day) * 24;
  var hour = hourF.floor();
  final minF = (hourF - hour) * 60;
  var minute = minF.floor();
  var second = ((minF - minute) * 60).round();
  if (second >= 60) {
    second -= 60;
    minute += 1;
  }
  if (minute >= 60) {
    minute -= 60;
    hour += 1;
  }
  if (hour >= 24) {
    hour -= 24;
    day += 1;
  }
  final month = e < 14 ? e - 1 : e - 13;
  final year = month > 2 ? c - 4716 : c - 4715;
  return LunarDateTime(year, month, day, hour, minute);
}

/// ΔT（TT - UT），秒
double _deltaT(int year, int month) {
  final y = year + (month - 0.5) / 12;
  double t;
  if (y < 1860) {
    t = y - 1860;
    return 7.62 + 0.5737 * t - 0.251754 * t * t + 0.01680668 * t * t * t -
        0.0004473624 * t * t * t * t + t * t * t * t * t / 233174;
  } else if (y < 1900) {
    t = y - 1900;
    return -2.79 + 1.494119 * t - 0.0598939 * t * t + 0.0061966 * t * t * t - 0.000197 * t * t * t * t;
  } else if (y < 1920) {
    t = y - 1900;
    return 21.20 + 0.84493 * t - 0.0761 * t * t + 0.0020936 * t * t * t;
  } else if (y < 1961) {
    t = y - 1920;
    return 29.07 + 0.407 * t - t * t / 233 + t * t * t / 2547;
  } else if (y < 1986) {
    t = y - 1975;
    return 45.45 + 1.067 * t - t * t / 260 - t * t * t / 718;
  } else if (y < 2005) {
    t = y - 2000;
    return 63.86 + 0.3345 * t - 0.060374 * t * t + 0.0017275 * t * t * t +
        0.000651814 * t * t * t * t + 0.00002373599 * t * t * t * t * t;
  } else if (y < 2050) {
    t = y - 2000;
    return 62.92 + 0.32217 * t + 0.005589 * t * t;
  } else {
    final u = (y - 1820) / 100;
    return -20 + 32 * u * u - 0.5628 * (2150 - y);
  }
}

// ============================================================
// 朔（新月）—— Meeus 第 49 章
// ============================================================

const List<double> _planetA = [
  299.77, 251.88, 251.83, 349.42, 84.66, 141.74, 207.14,
  154.84, 34.52, 207.19, 291.34, 161.72, 239.56, 331.55,
];
const List<double> _planetCoef = [
  0.000325, 0.000165, 0.000164, 0.000126, 0.000110, 0.000062,
  0.000060, 0.000056, 0.000047, 0.000042, 0.000040, 0.000037,
  0.000035, 0.000023,
];
const List<double> _planetRate = [
  0.107408, 0.016321, 26.651886, 36.412478,
  18.206239, 53.303771, 2.453732, 7.306860,
  27.261239, 0.121824, 1.844379, 24.198154,
  25.513099, 3.592518,
];

/// 第 k 个朔的时刻（TT 儒略日）
double _newMoonJDE(int k) {
  final t = k / 1236.85;
  final t2 = t * t;
  final t3 = t2 * t;
  final t4 = t3 * t;
  var jd = 2451550.09766 +
      _synodic * k +
      0.00015437 * t2 -
      0.000000150 * t3 +
      0.00000000073 * t4;
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  final m = _mod360(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3);
  final mp = _mod360(201.5643 + 385.81693528 * k + 0.0107582 * t2 + 0.00001238 * t3 - 0.000000058 * t4);
  final f = _mod360(160.7108 + 390.67050284 * k - 0.0016118 * t2 - 0.00000227 * t3 + 0.000000011 * t4);

  jd += -0.40720 * math.sin(mp * _rad) +
      0.17241 * e * math.sin(m * _rad) +
      0.01608 * math.sin(2 * mp * _rad) +
      0.01039 * math.sin(2 * f * _rad) +
      0.00739 * e * math.sin((mp - m) * _rad) -
      0.00514 * e * math.sin((mp + m) * _rad) +
      0.00208 * e * e * math.sin(2 * m * _rad) -
      0.00111 * math.sin((mp - 2 * f) * _rad) -
      0.00057 * math.sin((mp + 2 * f) * _rad) +
      0.00056 * e * math.sin((2 * mp + m) * _rad) -
      0.00042 * math.sin(3 * mp * _rad) +
      0.00042 * e * math.sin((m + 2 * f) * _rad) +
      0.00038 * e * math.sin((m - 2 * f) * _rad) -
      0.00024 * e * math.sin((2 * mp - m) * _rad) -
      0.00017 * math.sin((125.04 - 1934.136 * t) * _rad) -
      0.00007 * math.sin((mp + 2 * m) * _rad) +
      0.00004 * math.sin((2 * mp - 2 * f) * _rad) +
      0.00004 * math.sin(3 * m * _rad) +
      0.00003 * math.sin((mp + m - 2 * f) * _rad) +
      0.00003 * math.sin((2 * mp + 2 * f) * _rad) -
      0.00003 * math.sin((mp + m + 2 * f) * _rad) +
      0.00003 * math.sin((mp - m + 2 * f) * _rad) -
      0.00002 * math.sin((mp - m - 2 * f) * _rad) -
      0.00002 * math.sin((3 * mp + m) * _rad) +
      0.00002 * math.sin(4 * mp * _rad);

  for (var i = 0; i < 14; i++) {
    jd += _planetCoef[i] * math.sin((_planetA[i] + k * _planetRate[i]) * _rad);
  }
  return jd;
}

/// 第 k 个朔的儒略日（北京时间日界，UT + 8h）
double _newMoonJD(int k) {
  final jde = _newMoonJDE(k);
  final approx = jdToGregorian(jde);
  return jde - _deltaT(approx.year, approx.month) / 86400.0 + _beijingOffset;
}

/// 第 k 个朔所在的「农历日零点」JD（北京 00:00）
///
/// 踩坑记录：农历日以北京时间 00:00 为界，而非朔日精确时刻。
/// 若直接用朔日时刻当月起点，当朔发生在白天时后续日期会少算 1 天。
double _newMoonDayStartJD(int k) {
  final g = jdToGregorian(_newMoonJD(k));
  return gregorianToJD(g.year, g.month, g.day) + _beijingOffset;
}

// ============================================================
// 节气
// ============================================================

/// 二十四节气名称（按太阳视黄经）
const Map<int, String> TERM_NAMES = {
  270: '冬至', 285: '小寒', 300: '大寒', 315: '立春', 330: '雨水', 345: '惊蛰',
  0: '春分', 15: '清明', 30: '谷雨', 45: '立夏', 60: '小满', 75: '芒种',
  90: '夏至', 105: '小暑', 120: '大暑', 135: '立秋', 150: '处暑', 165: '白露',
  180: '秋分', 195: '寒露', 210: '霜降', 225: '立冬', 240: '小雪', 255: '大雪',
};

/// 二十四节气顺序（从冬至开始）
const List<int> TERM_ORDER = [
  270, 285, 300, 315, 330, 345, 0, 15, 30, 45, 60, 75,
  90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240, 255,
];

/// 某公历年某节气的时刻（儒略日，UT）
///
/// 精度策略：权威表优先，天文算法兜底。两条路径都必须返回 **UT 儒略日**，
/// 由 [LunarEngine.termDate] 统一加北京偏移 —— 不要在分支里各自换算时区。
double _termJD(int year, int termLon) {
  final lon = _mod360(termLon.toDouble()).toInt();

  final table = TERM_TIME_TABLE[year];
  final entry = table?[lon];
  if (entry != null) {
    final s = entry;
    final sp = s.split(' ');
    final md = sp[0].split('-');
    final hm = sp[1].split(':');
    // 表中为北京时间，北京时 = UT + 8h
    return gregorianToJD(year, int.parse(md[0]), int.parse(md[1])) +
        (int.parse(hm[0]) * 3600 + int.parse(hm[1]) * 60 - 8 * 3600) / 86400.0;
  }

  // 兜底：天文算法。_solarLongitudeTime 内部经 _toJDE 完成 UT→TT 换算，
  // 返回值已是 UT 儒略日，这里不要再减 ΔT 或加北京偏移。
  // （旧版本在已换算的基础上又减 ΔT、又两次加北京偏移，净误差约 -4 小时。）
  final jan1 = gregorianToJD(year, 1, 1);
  final doy = _mod360(lon - 285.0) / 0.9856 + 1;
  var jd = _solarLongitudeTime(lon.toDouble(), jan1 + doy);
  var g = jdToGregorian(jd);
  if (g.year != year) {
    jd = _solarLongitudeTime(lon.toDouble(), jan1 + doy - 365.25);
    g = jdToGregorian(jd);
    if (g.year != year) {
      jd = _solarLongitudeTime(lon.toDouble(), jan1 + doy + 365.25);
    }
  }
  return jd;
}

// ============================================================
// 农历引擎公开 API
// ============================================================

class LunarEngine {
  LunarEngine._();

  static final Map<int, _LunarYearInfo> _yearCache = {};

  /// 某年闰哪个月（0 = 无闰月）
  static int leapMonthNumber(int lunarYear) => LEAP_MONTH_TABLE[lunarYear] ?? 0;

  /// 某年某节气的公历时刻（北京时间）
  static LunarDateTime termDate(int year, int termLon) =>
      jdToGregorian(_termJD(year, termLon) + _beijingOffset);

  /// 某年某节气名称
  static String termName(int termLon) => TERM_NAMES[_mod360(termLon.toDouble()).toInt()] ?? '';

  /// 定位某农历年正月初一对应的朔日序号
  static int _findNewYearK(int lunarYear) {
    final anchor = SPRING_FESTIVAL_ANCHOR[lunarYear];

    // 春节必落在公历 [lunarYear-1 年 1/21, lunarYear 年 2/21] 窗口内
    final ws = gregorianToJD(lunarYear - 1, 1, 21) + _beijingOffset;
    final we = gregorianToJD(lunarYear, 2, 21) + _beijingOffset;
    final kStart = ((ws - 2451550.09766) / _synodic).floor();
    final kEnd = ((we - 2451550.09766) / _synodic).ceil();

    final candidates = <int>[];
    for (var k = kStart; k <= kEnd; k++) {
      final g = jdToGregorian(_newMoonJD(k));
      final inWindow = (g.year == lunarYear - 1 && ((g.month == 1 && g.day >= 21) || g.month == 2)) ||
          (g.year == lunarYear && g.month == 1 && g.day <= 21);
      if (inWindow) candidates.add(k);
    }

    if (candidates.isEmpty) {
      return ((gregorianToJD(lunarYear, 7, 1) + _beijingOffset - 2451550.09766) / _synodic).round();
    }

    // 优先：权威锚点精确匹配
    if (anchor != null) {
      final parts = anchor.split('-');
      final am = int.parse(parts[0]);
      final ad = int.parse(parts[1]);
      for (final k in candidates) {
        final g = jdToGregorian(_newMoonJD(k));
        if (g.month == am && g.day == ad) return k;
      }
    }

    // 兜底：冬至后第二个朔（子月→丑月→正月）
    // 注意帧基准：_termJD 返回 UT 儒略日，_newMoonJD 返回北京时儒略日
    // （UT + 8h），比较前必须归到同一帧，否则差 1/3 天
    final wsJD = _termJD(lunarYear - 1, 270);
    int? ziK;
    for (var k = kStart - 6; k <= kEnd; k++) {
      final start = _newMoonJD(k) - _beijingOffset;
      if (wsJD >= start && wsJD < _newMoonJD(k + 1) - _beijingOffset) {
        ziK = k;
        break;
      }
    }
    if (ziK != null) return ziK + 2;

    return candidates.last;
  }

  /// 构建某农历年的月结构
  static _LunarYearInfo _buildLunarYear(int lunarYear) {
    final cached = _yearCache[lunarYear];
    if (cached != null) return cached;

    final newYearK = _findNewYearK(lunarYear);
    final leap = leapMonthNumber(lunarYear);

    final months = <_LunarMonth>[];
    var k = newYearK;
    // 遍历 12 个正常月；若该年有闰月，在第 leap 个正常月之后插入闰 leap 月。
    // 这样总月数 = 12 + (leap > 0 ? 1 : 0)，恰好 12 或 13。
    for (var m = 1; m <= 12; m++) {
      final start = _newMoonDayStartJD(k);
      final next = _newMoonDayStartJD(k + 1);
      months.add(_LunarMonth(start, next - start, m, false));
      k += 1;

      if (leap > 0 && m == leap) {
        final lStart = _newMoonDayStartJD(k);
        final lNext = _newMoonDayStartJD(k + 1);
        months.add(_LunarMonth(lStart, lNext - lStart, leap, true));
        k += 1;
      }
    }

    final info = _LunarYearInfo(
      lunarYear,
      _newMoonDayStartJD(newYearK),
      months,
    );
    _yearCache[lunarYear] = info;
    return info;
  }

  /// 农历 → 公历
  ///
  /// [lunarDay] 超过当月实际天数时钳制到月末（如小月求「三十」得到廿九），
  /// 而不是静默滚到下月初一 —— 否则自定义「农历三月三十生日」在小月年份
  /// 会错算成四月初一。
  static LunarDateTime lunarToSolar(int lunarYear, int lunarMonth, int lunarDay,
      [bool isLeap = false]) {
    final info = _buildLunarYear(lunarYear);
    var month = _monthOf(info, lunarMonth, isLeap);
    // 该年没有这个闰月时，回退到同名平月，而不是返回 1900 哨兵日期
    month ??= isLeap ? _monthOf(info, lunarMonth, false) : null;
    if (month == null) return const LunarDateTime(1900, 1, 1);
    final day = lunarDay.clamp(1, month.length.round());
    return jdToGregorian(month.start + (day - 1));
  }

  static _LunarMonth? _monthOf(_LunarYearInfo info, int number, bool isLeap) {
    for (final m in info.months) {
      if (m.number == number && m.isLeap == isLeap) return m;
    }
    return null;
  }

  /// 公历 → 农历
  static LunarDate solarToLunar(int year, int month, int day) {
    final jd = gregorianToJD(year, month, day) + _beijingOffset;
    for (final ly in [year, year - 1, year + 1]) {
      final info = _buildLunarYear(ly);
      for (final m in info.months) {
        if (jd >= m.start && jd < m.start + m.length) {
          final dayNum = (jd - m.start + 1e-9).floor() + 1;
          return LunarDate(ly, m.number, dayNum, isLeap: m.isLeap);
        }
      }
    }
    return LunarDate(year, 1, 1);
  }

  /// 除夕：腊月的最后一天
  static LunarDateTime lunarNewYearEve(int lunarYear) {
    final info = _buildLunarYear(lunarYear);
    for (final m in info.months) {
      if (m.number == 12 && !m.isLeap) {
        return jdToGregorian(m.start + m.length - 1);
      }
    }
    return const LunarDateTime(1900, 1, 1);
  }

  /// 调试：返回某农历年 13/12 个月的长序列
  @visibleForTesting
  static List<double> debugMonthLengths(int lunarYear) {
    final info = _buildLunarYear(lunarYear);
    return info.months.map((m) => m.length).toList();
  }

  /// 某农历年总天数（354 或 355，平年；383 或 384，闰年）
  static int lunarYearDays(int lunarYear) {
    final lengths = debugMonthLengths(lunarYear);
    var total = 0;
    for (final l in lengths) {
      total += l.round();
    }
    return total;
  }

  /// 某农历年某月的天数
  static int lunarMonthDays(int lunarYear, int lunarMonth, bool isLeap) {
    final info = _buildLunarYear(lunarYear);
    for (final m in info.months) {
      if (m.number == lunarMonth && m.isLeap == isLeap) {
        return m.length.round();
      }
    }
    return 30;
  }
}
