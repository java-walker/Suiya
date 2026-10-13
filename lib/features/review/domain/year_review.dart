/// 岁忆 · 年度回望统计（domain 层，纯 Dart）
///
/// 一年将尽时，用这一年的记录生成一张回顾卡片。
/// 只做统计与文案，不碰 UI 与存储。
library;

import '../../record/domain/memory_record.dart';

/// 一年中的某一天
class DayMark {
  final String festivalId;
  final String festivalName;
  final int month;
  final int day;
  final String lunarText;
  final bool recorded;
  final String? recordTitle;

  const DayMark({
    required this.festivalId,
    required this.festivalName,
    required this.month,
    required this.day,
    required this.lunarText,
    required this.recorded,
    this.recordTitle,
  });
}

/// 年度回望数据
class YearReview {
  final int year;

  /// 这一年发生了多少天
  final int totalDays;

  /// 记录了多少天
  final int recordedDays;

  /// 记录了多少张照片
  final int photoCount;

  /// 参与过的人（去重）
  final List<String> people;

  /// 用过的标签（按次数降序）
  final List<(String, int)> topTags;

  /// 有记录的节点
  final List<DayMark> marks;

  const YearReview({
    required this.year,
    required this.totalDays,
    required this.recordedDays,
    required this.photoCount,
    required this.people,
    required this.topTags,
    required this.marks,
  });

  /// 记录率（0~1），用于"你认真过了多少个日子"
  double get coverage => totalDays == 0 ? 0 : recordedDays / totalDays;

  /// 一句话总结
  String get headline {
    if (recordedDays == 0) return '$year 年，你一个日子也没记下。';
    final pct = (coverage * 100).round();
    if (recordedDays == 1) return '$year 年，你在 1 个日子里留下了记号。';
    return '$year 年，你在 $recordedDays 个日子里留下了记号。';
  }

  /// 覆盖率评语
  String get comment {
    final c = coverage;
    if (recordedDays == 0) return '明年开始也不迟';
    if (c < 0.2) return '开了个头，继续';
    if (c < 0.5) return '记下了不少呢';
    if (c < 0.8) return '很认真地在过日子';
    return '几乎一天没落下';
  }

  /// 首个 / 末个记录，用于"从…到…"
  String? get span {
    final r = marks.where((m) => m.recorded).toList();
    if (r.isEmpty) return null;
    return '${r.first.month}/${r.first.day} — ${r.last.month}/${r.last.day}';
  }
}

/// 从记录列表算出年度回望
///
/// [allDays] 是这一年的所有岁时节点（由 presentation 层从节日库算出并传入），
/// 这样 domain 层不需要依赖节日库。
YearReview buildYearReview({
  required int year,
  required List<DayMark> allDays,
  required List<MemoryRecord> records,
  int photoCount = 0,
}) {
  // 记录按 (festivalId) 归并：同一年内一个节日一条
  final byFest = <String, MemoryRecord>{
    for (final r in records)
      if (r.festivalId != null) r.festivalId!: r,
  };

  final marks = allDays
      .map((d) => DayMark(
            festivalId: d.festivalId,
            festivalName: d.festivalName,
            month: d.month,
            day: d.day,
            lunarText: d.lunarText,
            recorded: byFest.containsKey(d.festivalId),
            recordTitle: byFest[d.festivalId]?.title,
          ))
      .toList()
    ..sort((a, b) {
      final c = a.month * 100 + a.day;
      final d = b.month * 100 + b.day;
      return c.compareTo(d);
    });

  // 参与人（去重，保持出现顺序）
  final people = <String>[];
  for (final r in records) {
    for (final p in r.participants) {
      if (!people.contains(p)) people.add(p);
    }
  }

  // 标签计数
  final tagCount = <String, int>{};
  for (final r in records) {
    for (final t in r.tags) {
      tagCount[t] = (tagCount[t] ?? 0) + 1;
    }
  }
  final topTags = tagCount.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return YearReview(
    year: year,
    totalDays: allDays.length,
    recordedDays: marks.where((m) => m.recorded).length,
    photoCount: photoCount,
    people: people,
    topTags: topTags.map((e) => (e.key, e.value)).toList(),
    marks: marks,
  );
}
