/// 岁忆 · 记录实体（domain 层）
///
/// 这一层**不 import flutter**，只用 dart:core —— 这样业务规则可以脱离 UI 单测，
/// 也保证将来换存储/换框架时不用重写。
library;

import '../../../core/lunar/lunar_engine.dart';

/// 循环规则：与节日库共用同一套判定，保证"手账节点"和"节日节点"算法一致。
enum Recurrence {
  /// 公历每年重复（母亲生日 3/20）
  solarAnnual,

  /// 公历单次（结婚纪念日）
  solarFixed,

  /// 农历每年重复（春节、中秋）
  lunarAnnual,

  /// 农历每月重复（初一、十五、廿三祭灶）
  lunarMonthly,

  /// 节气（清明、冬至）
  solarTerm,

  /// 不重复的一次性事件
  once,
}

extension RecurrenceX on Recurrence {
  String get label => switch (this) {
        Recurrence.solarAnnual => '公历每年',
        Recurrence.solarFixed => '公历单次',
        Recurrence.lunarAnnual => '农历每年',
        Recurrence.lunarMonthly => '农历每月',
        Recurrence.solarTerm => '节气',
        Recurrence.once => '仅此一次',
      };

  /// 从数据库字符串解析
  static Recurrence parse(String raw) => Recurrence.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => Recurrence.once,
      );
}

/// 同步策略：隐私优先，墓园等敏感内容默认绝不上传。
enum SyncPolicy {
  localOnly,
  always;

  String get label => this == SyncPolicy.localOnly ? '仅本地' : '可同步';
  String get dbValue => this == SyncPolicy.localOnly ? 'LOCAL_ONLY' : 'ALWAYS';

  static SyncPolicy parse(String raw) =>
      raw == 'ALWAYS' ? SyncPolicy.always : SyncPolicy.localOnly;
}

/// 一条结构化问答
class QaItem {
  final String question;
  final String answer;

  const QaItem(this.question, this.answer);

  bool get isAnswered => answer.trim().isNotEmpty;
}

/// 一次岁时记录。
///
/// 语义：**[festivalId] 在 [year] 年发生的那一次**。
/// 同一个节日在不同年份是不同记录（2026 中秋 ≠ 2027 中秋）。
class MemoryRecord {
  final String id;

  /// 关联的节日 id（可为空，表示纯自定义记录）
  final String? festivalId;
  final int year;
  final String title;
  final String text;
  final List<QaItem> qa;
  final Recurrence recurrence;
  final int advanceDays;
  final bool remindOn;
  final List<String> participants;
  final List<String> tags;
  final double? lat;
  final double? lng;
  final String? placeId;
  final String? address;
  final SyncPolicy syncPolicy;
  final int createdAt;
  final int updatedAt;

  const MemoryRecord({
    required this.id,
    this.festivalId,
    required this.year,
    required this.title,
    this.text = '',
    this.qa = const [],
    this.recurrence = Recurrence.once,
    this.advanceDays = 1,
    this.remindOn = false,
    this.participants = const [],
    this.tags = const [],
    this.lat,
    this.lng,
    this.placeId,
    this.address,
    this.syncPolicy = SyncPolicy.localOnly,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 记录发生日期（公历）。解析器由 presentation 层在启动时注入，
  /// 这样 domain 层不必反向依赖 festival.dart（保持纯 Dart 可测）。
  /// 发生日期（公历）。注意引擎里的 `LunarDateTime` 字段就是公历年月日。
  LunarDateTime? get date {
    final id = festivalId;
    if (id == null) return null;
    return _festivalResolver?.call(id, year);
  }

  static LunarDateTime? Function(String festivalId, int year)? _festivalResolver;

  static void bindFestivalResolver(
      LunarDateTime? Function(String festivalId, int year) resolver) {
    _festivalResolver = resolver;
  }

  /// copyWith 里可空字段的「未传」哨兵：
  /// 直接用 `??` 的话，编辑页取消地点后传 null 会被当成「保留旧值」，
  /// UI 显示已清除但落库的记录仍带着旧地点/坐标。
  static const Object _unset = Object();

  MemoryRecord copyWith({
    String? title,
    String? text,
    List<QaItem>? qa,
    int? advanceDays,
    bool? remindOn,
    List<String>? participants,
    List<String>? tags,
    Object? lat = _unset,
    Object? lng = _unset,
    Object? placeId = _unset,
    Object? address = _unset,
    SyncPolicy? syncPolicy,
    int? updatedAt,
  }) {
    return MemoryRecord(
      id: id,
      festivalId: festivalId,
      year: year,
      title: title ?? this.title,
      text: text ?? this.text,
      qa: qa ?? this.qa,
      recurrence: recurrence,
      advanceDays: advanceDays ?? this.advanceDays,
      remindOn: remindOn ?? this.remindOn,
      participants: participants ?? this.participants,
      tags: tags ?? this.tags,
      lat: identical(lat, _unset) ? this.lat : lat as double?,
      lng: identical(lng, _unset) ? this.lng : lng as double?,
      placeId:
          identical(placeId, _unset) ? this.placeId : placeId as String?,
      address:
          identical(address, _unset) ? this.address : address as String?,
      syncPolicy: syncPolicy ?? this.syncPolicy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 用于"未来 N 天"筛选
  int? get daysUntil {
    final d = date;
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day).difference(today).inDays;
  }

  /// 公历 DateTime（给需要 DateTime 的地方用）
  DateTime? get solarDate {
    final d = date;
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// 展示用的日期文本（含农历）
  String get displayDate {
    final d = date;
    if (d == null) return '未定日期';
    final l = LunarEngine.solarToLunar(d.year, d.month, d.day);
    return '${d.month}月${d.day}日 · 农历${l.month}月${l.day}日';
  }
}

/// 时间轴节点的四种状态（对应需求 F2）
enum NodeStatus {
  /// 有当年记录
  recorded,

  /// 下一个待发生
  upcoming,

  /// 已过但没记 —— 唤回钩子
  missed,

  /// 与本次记录无关的普通日期
  none,
}
