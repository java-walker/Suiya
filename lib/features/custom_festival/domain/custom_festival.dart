/// 岁忆 · 用户自定义日子（domain 层，纯 Dart）
///
/// 与内置 [Festival] 的差别：数据在 SQLite 里，用户自己增删改。
/// 通过 [CustomFestival.asFestival] 转成同一套模型，
/// 让时间轴、记录编辑、提醒都能无差别处理。
library;

import '../../../core/festival/festival.dart';
import '../../../core/lunar/lunar_engine.dart';

/// 自定义日子的循环规则（比内置的少一档：不支持节气，用户无法准确定位黄经）
enum CustomRecurrence {
  /// 公历某一天，只在 [anchorYear] 那一年出现（适合「3 月 20 日母亲生日」当年记一次）
  solarOnce,

  /// 公历某月某日，每年重复
  solarAnnual,

  /// 农历某月某日，每年重复
  lunarAnnual,

  /// 农历每月某日（初一 / 十五 生日）
  lunarMonthly;

  String get label => switch (this) {
        CustomRecurrence.solarOnce => '仅此一次',
        CustomRecurrence.solarAnnual => '公历每年',
        CustomRecurrence.lunarAnnual => '农历每年',
        CustomRecurrence.lunarMonthly => '农历每月',
      };

  String get hint => switch (this) {
        CustomRecurrence.solarOnce => '只在所选年份出现一次，之后不再出现',
        CustomRecurrence.solarAnnual => '如：3 月 20 日 母亲生日',
        CustomRecurrence.lunarAnnual => '如：农历八月十五 自家忌日',
        CustomRecurrence.lunarMonthly => '如：农历十五 奶奶生日',
      };

  static CustomRecurrence parse(String? raw) =>
      CustomRecurrence.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => CustomRecurrence.solarAnnual,
      );
}

/// 自定义节日
class CustomFestival {
  final String id;
  final String name;
  final CustomRecurrence recurrence;
  final int? solarMonth;
  final int? solarDay;
  final int? lunarMonth;
  final int? lunarDay;
  final int defaultAdvanceDays;
  final String? note;

  /// 自定义引导提问（可为空，为空时按循环类型给通用问题）
  final List<PromptTemplate> prompts;

  /// 排序序号（越小越靠前）
  final int sortIndex;

  /// 「仅此一次」的锚定年份；其他循环类型为 null
  final int? anchorYear;

  final int createdAt;
  final int updatedAt;

  const CustomFestival({
    required this.id,
    required this.name,
    required this.recurrence,
    this.solarMonth,
    this.solarDay,
    this.lunarMonth,
    this.lunarDay,
    this.defaultAdvanceDays = 1,
    this.note,
    this.prompts = const [],
    this.sortIndex = 0,
    this.anchorYear,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 是否是「只在今年」的一次性日子
  bool get isOnceOnly => recurrence == CustomRecurrence.solarOnce;

  /// 一次性日子实际生效的年份：用户选的年份，未选则退回创建年份
  int get effectiveAnchorYear =>
      anchorYear ?? _yearOf(createdAt) ?? DateTime.now().year;

  static int? _yearOf(int msEpoch) {
    if (msEpoch <= 0) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(msEpoch);
    return d.year;
  }

  /// [asFestival] 不带年份信息，仅供列表分类与提示词使用。
  /// 计算真实日期一律走 [dateIn]，否则「仅此一次」会被当成每年重复。
  Festival asFestival() {
    final rt = switch (recurrence) {
      CustomRecurrence.solarOnce => RecurrenceType.solarOnce,
      CustomRecurrence.solarAnnual => RecurrenceType.solarAnnual,
      CustomRecurrence.lunarAnnual => RecurrenceType.lunarAnnual,
      CustomRecurrence.lunarMonthly => RecurrenceType.lunarMonthly,
    };
    return Festival(
      id: id,
      name: name,
      recurrence: rt,
      solarMonth: solarMonth,
      solarDay: solarDay,
      lunarMonth: lunarMonth,
      lunarDay: lunarDay,
      category: FestivalCategory.personal,
      defaultAdvanceDays: defaultAdvanceDays,
      prompts: prompts,
      note: note ?? _defaultNote(),
    );
  }

  String? _defaultNote() {
    switch (recurrence) {
      case CustomRecurrence.solarOnce:
        return '$solarMonth 月 $solarDay 日 · 仅 $effectiveAnchorYear 年一次';
      case CustomRecurrence.solarAnnual:
        return '公历 $solarMonth 月 $solarDay 日 · 每年';
      case CustomRecurrence.lunarAnnual:
        return '农历 $lunarMonth 月 $lunarDay 日 · 每年';
      case CustomRecurrence.lunarMonthly:
        return '农历每月 $lunarDay 日';
    }
  }

  /// 该节日在 [year] 年的公历日期；不适用时返回 null。
  ///
  /// 「仅此一次」只有 anchorYear 命中才返回日期，
  /// 这样时间轴在其它年份自然不会渲染出这个节点。
  LunarDateTime? dateIn(int year) {
    if (isOnceOnly && year != effectiveAnchorYear) return null;
    return asFestival().dateIn(year);
  }

  /// 是否在 [year] 年出现
  bool occursIn(int year) =>
      !isOnceOnly || year == effectiveAnchorYear;

  /// 下一次日期文本，供列表展示
  String nextLabel({DateTime? from}) {
    final now = DateTime.now();
    final f = from ?? now;
    if (isOnceOnly) {
      final anchor = effectiveAnchorYear;
      final d = dateIn(anchor);
      if (d == null) return '';
      final diff = DateTime(d.year, d.month, d.day)
          .difference(DateTime(f.year, f.month, f.day))
          .inDays;
      final md = '${d.month}/${d.day}';
      if (diff == 0) return '$md · 就是今天';
      if (diff > 0) return '$md · 还有 $diff 天';
      if (f.year > anchor) return '已过（$anchor 年那次）';
      return '$md · 已过 ${-diff} 天';
    }
    final next = asFestival().nextOccurrence(f);
    if (next == null) return '';
    // 与内置节日一致：用零点归一后的差值。直接用带时刻的 now，
    // 「明天 00:00」与「今天 10:00」差 14 小时 → inDays==0 → 误显示「就是今天」
    final days = DateTime(next.year, next.month, next.day)
        .difference(DateTime(f.year, f.month, f.day))
        .inDays;
    final md = '${next.month}/${next.day}';
    if (days == 0) return '就是今天';
    if (days < 0) return md;
    return '$md · 还有 $days 天';
  }

  /// copyWith 里可空字段的「未传」哨兵：
  /// 直接用 `??` 的话，编辑页清空备注/切换循环类型时传 null 会被当成
  /// 「保留旧值」，导致备注复活、DB 里残留与 recurrence 矛盾的脏字段。
  static const Object _unset = Object();

  CustomFestival copyWith({
    String? name,
    CustomRecurrence? recurrence,
    Object? solarMonth = _unset,
    Object? solarDay = _unset,
    Object? lunarMonth = _unset,
    Object? lunarDay = _unset,
    int? defaultAdvanceDays,
    Object? note = _unset,
    List<PromptTemplate>? prompts,
    int? sortIndex,
    int? anchorYear,
    int? updatedAt,
  }) {
    final nextRecurrence = recurrence ?? this.recurrence;
    return CustomFestival(
      id: id,
      name: name ?? this.name,
      recurrence: nextRecurrence,
      solarMonth:
          identical(solarMonth, _unset) ? this.solarMonth : solarMonth as int?,
      solarDay: identical(solarDay, _unset) ? this.solarDay : solarDay as int?,
      lunarMonth:
          identical(lunarMonth, _unset) ? this.lunarMonth : lunarMonth as int?,
      lunarDay: identical(lunarDay, _unset) ? this.lunarDay : lunarDay as int?,
      defaultAdvanceDays: defaultAdvanceDays ?? this.defaultAdvanceDays,
      note: identical(note, _unset) ? this.note : note as String?,
      prompts: prompts ?? this.prompts,
      sortIndex: sortIndex ?? this.sortIndex,
      // 非一次性循环不需要锚定年份，显式清掉避免留下脏数据
      anchorYear: nextRecurrence == CustomRecurrence.solarOnce
          ? (anchorYear ?? this.anchorYear)
          : null,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 生成全局唯一 id（前缀区分，避免和内置节日冲突）
  static String newId() =>
      'custom_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}