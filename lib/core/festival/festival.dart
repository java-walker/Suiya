/// 岁忆 · 节日定义与模板
///
/// 这是 App 的「内容层」——决定用户看到哪些日子、收到哪些提醒。
library;



import '../lunar/lunar_engine.dart';

/// 循环类型
enum RecurrenceType {
  /// 公历固定单次（如结婚纪念日）
  solarOnce,

  /// 公历年度循环（如母亲生日 3/20）
  solarAnnual,

  /// 农历年度循环（春节、中秋、端午）
  lunarAnnual,

  /// 农历每月固定日（初一、十五、廿三祭灶）
  lunarMonthly,

  /// 节气（清明、冬至）
  solarTerm,
}

/// 节日分类
enum FestivalCategory {
  /// 岁时节日（春节、中秋、端午）
  seasonal,

  /// 祭祖扫墓（清明、冬至、七月半）
  memorial,

  /// 拜神祭祀（初一、十五、廿三）
  worship,

  /// 节气
  term,

  /// 人生纪念（生日、婚纪念）
  personal,
}

/// 引导提问模板
class PromptTemplate {
  final String question;
  final String? placeholder;

  const PromptTemplate(this.question, {this.placeholder});
}

/// 节日定义
class Festival {
  final String id;
  final String name;
  final RecurrenceType recurrence;

  /// 公历锚点（月, 日）—— solarAnnual / solarOnce / solarTerm 用
  final int? solarMonth;
  final int? solarDay;

  /// 农历锚点（月, 日）—— lunarAnnual / lunarMonthly 用
  final int? lunarMonth;
  final int? lunarDay;

  /// 节气黄经 —— solarTerm 用
  final int? termLongitude;

  final FestivalCategory category;

  /// 默认提前提醒天数
  final int defaultAdvanceDays;

  /// 引导提问
  final List<PromptTemplate> prompts;

  /// 简短说明
  final String? note;

  const Festival({
    required this.id,
    required this.name,
    required this.recurrence,
    this.solarMonth,
    this.solarDay,
    this.lunarMonth,
    this.lunarDay,
    this.termLongitude,
    required this.category,
    this.defaultAdvanceDays = 1,
    this.prompts = const [],
    this.note,
  });

  /// 计算该节日在 [year] 年的公历日期
  ///
  /// [lunarYearOffset] 用于处理「腊月/十一月」这类跨年场景：
  /// 例如 2025 年春节是 2025-01-29，而腊八在 2025-02-07（已是农历 2024 年腊月）。
  LunarDateTime? dateIn(int year) {
    switch (recurrence) {
      case RecurrenceType.solarOnce:
      case RecurrenceType.solarAnnual:
        if (solarMonth == null || solarDay == null) return null;
        return LunarDateTime(year, solarMonth!, solarDay!);

      case RecurrenceType.solarTerm:
        if (termLongitude == null) return null;
        return LunarEngine.termDate(year, termLongitude!);

      case RecurrenceType.lunarAnnual:
        if (lunarMonth == null || lunarDay == null) return null;
        // 农历年春节通常落在同年 1-2 月；
        // 若算出的日期在 12 月，说明该农历年春节在次年，需用前一年
        var result = LunarEngine.lunarToSolar(year, lunarMonth!, lunarDay!);
        if (result.year > year) {
          result = LunarEngine.lunarToSolar(year - 1, lunarMonth!, lunarDay!);
        }
        // 除夕等「腊月最后一天」需特殊处理：若第 30 天不存在，退化为该月最后一天
        if (lunarMonth == 12 && lunarDay == 30) {
          final lunarYear = result.year - 1; // 除夕属上一农历年
          final eve = LunarEngine.lunarNewYearEve(lunarYear);
          if (eve.year == year) return eve;
        }
        return result;

      case RecurrenceType.lunarMonthly:
        if (lunarMonth == null || lunarDay == null) return null;
        // 每月固定日，取该农历年中的第一个匹配
        final solar = LunarEngine.lunarToSolar(year, lunarMonth!, lunarDay!);
        return solar;
    }
  }

  /// 计算下一次发生的日期（从 [from] 起）
  LunarDateTime? nextOccurrence(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    if (recurrence == RecurrenceType.lunarMonthly) {
      // 每月固定日：逐农历月展开找下一次，而不是只看正月初一那次 ——
      // 否则 2 月之后 nextOccurrence 恒为过去，这些日子永远显示「已错过」
      for (var y = from.year - 1; y <= from.year + 2; y++) {
        if (y < 1901) continue;
        for (var m = 1; m <= 12; m++) {
          if (lunarMonth == null || lunarDay == null) return null;
          final solar = LunarEngine.lunarToSolar(y, m, lunarDay!);
          final dt = DateTime(solar.year, solar.month, solar.day);
          if (dt.isAfter(today)) return solar;
        }
      }
      return null;
    }
    final startYear = from.year;
    for (var y = startYear; y <= startYear + 2; y++) {
      final d = dateIn(y);
      if (d == null) continue;
      final dt = DateTime(d.year, d.month, d.day);
      if (dt.isAfter(today)) {
        return d;
      }
    }
    return null;
  }

  /// 农历每月型：某年内的所有发生日
  List<LunarDateTime> occurrencesInLunarYear(int lunarYear) {
    if (recurrence != RecurrenceType.lunarMonthly) return const [];
    final len = LunarEngine.lunarMonthDays(lunarYear, lunarMonth ?? 1, false);
    if ((lunarDay ?? 1) > len) return const [];
    return [LunarEngine.lunarToSolar(lunarYear, lunarMonth!, lunarDay!)];
  }
}

/// 节日模板
class FestivalTemplate {
  final String id;
  final String name;
  final String description;
  final List<String> festivalIds;

  const FestivalTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.festivalIds,
  });
}

// ============================================================
// 节日库
// ============================================================

class Festivals {
  Festivals._();

  // ---------- 岁时节日 ----------
  static const springFestival = Festival(
    id: 'spring_festival',
    name: '春节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 1,
    lunarDay: 1,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 7,
    note: '农历正月初一',
    prompts: [
      PromptTemplate('今年回的是哪边老家？', placeholder: '如：老家 / 岳父母家 / 原地'),
      PromptTemplate('做了什么年夜饭？', placeholder: '几道菜、最拿手的那道'),
      PromptTemplate('收到的最意外的东西？'),
    ],
  );

  static const yuanxiao = Festival(
    id: 'yuanxiao',
    name: '元宵节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 1,
    lunarDay: 15,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    prompts: [PromptTemplate('今年元宵做了什么？', placeholder: '汤圆 / 灯会 / 家人相聚')],
  );

  static const longtaitou = Festival(
    id: 'longtaitou',
    name: '龙抬头',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 2,
    lunarDay: 2,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 1,
    note: '农历二月初二，民间理发日',
  );

  static const duanwu = Festival(
    id: 'duanwu',
    name: '端午节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 5,
    lunarDay: 5,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    prompts: [
      PromptTemplate('今年吃了什么粽子？', placeholder: '如：咸肉粽 / 碱水粽'),
      PromptTemplate('有没有参加家乡的龙舟赛？'),
    ],
  );

  static const qixi = Festival(
    id: 'qixi',
    name: '七夕',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 7,
    lunarDay: 7,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    note: '农历七月初七',
  );

  static const zhongyuan = Festival(
    id: 'zhongyuan',
    name: '中元节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 7,
    lunarDay: 15,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 3,
    note: '农历七月十五，鬼节',
    prompts: [PromptTemplate('今年做了什么事？', placeholder: '祭祀 / 普渡 / 家祭')],
  );

  static const midAutumn = Festival(
    id: 'mid_autumn',
    name: '中秋节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 8,
    lunarDay: 15,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 7,
    prompts: [
      PromptTemplate('今年在哪家过？', placeholder: '如：奶奶家 / 岳父家 / 酒店'),
      PromptTemplate('带了什么礼物 / 做了什么菜？'),
      PromptTemplate('家里人说了什么让你记住的话？'),
    ],
  );

  static const chongyang = Festival(
    id: 'chongyang',
    name: '重阳节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 9,
    lunarDay: 9,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    note: '农历九月初九，敬老日',
  );

  static const laba = Festival(
    id: 'laba',
    name: '腊八节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 12,
    lunarDay: 8,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    prompts: [PromptTemplate('今年熬了腊八粥吗？', placeholder: '配什么料')],
  );

  static const xiaonian = Festival(
    id: 'xiaonian',
    name: '小年',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 12,
    lunarDay: 23,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 3,
    note: '腊月廿三（北方）/ 廿四（南方）',
  );

  static const chuxi = Festival(
    id: 'chuxi',
    name: '除夕',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 12,
    lunarDay: 30,
    category: FestivalCategory.seasonal,
    defaultAdvanceDays: 7,
    note: '腊月最后一天',
  );

  // ---------- 祭祖扫墓 ----------
  static const qingming = Festival(
    id: 'qingming',
    name: '清明',
    recurrence: RecurrenceType.solarTerm,
    termLongitude: 15,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 3,
    note: '节气 · 扫墓祭祖',
    prompts: [
      PromptTemplate('今年和谁一起去的？'),
      PromptTemplate('墓地在哪？', placeholder: '可从「墓园」中选择，自动带出位置'),
      PromptTemplate('今天做了什么？', placeholder: '扫墓 / 祭拜 / 修墓 / 远路'),
      PromptTemplate('想对祖先说的话'),
    ],
  );

  static const winterSolstice = Festival(
    id: 'winter_solstice',
    name: '冬至',
    recurrence: RecurrenceType.solarTerm,
    termLongitude: 270,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 1,
    note: '节气 · 北方祭祖、南方吃汤圆',
    prompts: [PromptTemplate('今年冬至吃了什么？', placeholder: '汤圆 / 饺子 / 羊肉')],
  );

  static const hantuo = Festival(
    id: 'hantuo',
    name: '寒食节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 2,
    lunarDay: 15,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 1,
    note: '农历二月十五，前后与清明相连',
  );

  static const hanshi = Festival(
    id: 'hanshi',
    name: '寒衣节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 10,
    lunarDay: 1,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 3,
    note: '农历十月初一，祭奠先人',
  );

  static const xiayuan = Festival(
    id: 'xiayuan',
    name: '下元节',
    recurrence: RecurrenceType.lunarAnnual,
    lunarMonth: 10,
    lunarDay: 15,
    category: FestivalCategory.memorial,
    defaultAdvanceDays: 1,
  );

  // ---------- 拜神祭祀（潮汕/客家习俗）----------
  static const chu_yi_festival = Festival(
    id: 'chu_yi',
    name: '初一 · 拜神',
    recurrence: RecurrenceType.lunarMonthly,
    lunarMonth: 1,
    lunarDay: 1,
    category: FestivalCategory.worship,
    defaultAdvanceDays: 1,
    note: '农历每月初一 · 潮汕/客家拜神日',
    prompts: [PromptTemplate('今天拜了哪些神？', placeholder: '如：福德正神 / 天官赐福')],
  );

  static const shi_wu_festival = Festival(
    id: 'shi_wu',
    name: '十五 · 拜神',
    recurrence: RecurrenceType.lunarMonthly,
    lunarMonth: 1,
    lunarDay: 15,
    category: FestivalCategory.worship,
    defaultAdvanceDays: 1,
    note: '农历每月十五 · 拜神日',
    prompts: [PromptTemplate('今天做了什么？', placeholder: '拜神 / 供奉祖先')],
  );

  static const jizao = Festival(
    id: 'jizao',
    name: '廿三 · 祭灶',
    recurrence: RecurrenceType.lunarMonthly,
    lunarMonth: 1,
    lunarDay: 23,
    category: FestivalCategory.worship,
    defaultAdvanceDays: 1,
    note: '农历每月廿三 · 小年祭灶',
  );

  static const weiya = Festival(
    id: 'weiya',
    name: '尾牙',
    recurrence: RecurrenceType.lunarMonthly,
    lunarMonth: 2,
    lunarDay: 15,
    category: FestivalCategory.worship,
    defaultAdvanceDays: 1,
    note: '农历二月十五 · 潮汕尾牙（牙忌）',
  );

  static const benyue_26_festival = Festival(
    id: 'benyue_26',
    name: '廿六 · 拜神',
    recurrence: RecurrenceType.lunarMonthly,
    lunarMonth: 1,
    lunarDay: 26,
    category: FestivalCategory.worship,
    defaultAdvanceDays: 1,
    note: '农历每月廿六 · 潮汕拜神日',
  );

  // ---------- 全部节日库 ----------
  static const all = <Festival>[
    springFestival, yuanxiao, longtaitou, duanwu, qixi, zhongyuan,
    midAutumn, chongyang, laba, xiaonian, chuxi,
    qingming, winterSolstice, hantuo, hanshi, xiayuan,
    chu_yi_festival, shi_wu_festival, jizao, weiya, benyue_26_festival,
  ];

  static Festival? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  static List<Festival> byCategory(FestivalCategory c) =>
      all.where((f) => f.category == c).toList();

  /// 全部二十四节气（24 个）
  ///
  /// 注意：清明与冬至在岁时传统中有特殊地位（扫墓/祭祖），
  /// 已在 memorial 分类单独定义（id: qingming / winter_solstice）。
  /// 此处仍列出 term_15 与 term_270，供「全量」模板作为纯节气提醒使用。
  static List<Festival> allTerms() {
    return [
      const Festival(id: 'term_315', name: '立春', recurrence: RecurrenceType.solarTerm,
          termLongitude: 315, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 春季开始'),
      const Festival(id: 'term_330', name: '雨水', recurrence: RecurrenceType.solarTerm,
          termLongitude: 330, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_345', name: '惊蛰', recurrence: RecurrenceType.solarTerm,
          termLongitude: 345, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 春雷始鸣'),
      const Festival(id: 'term_0', name: '春分', recurrence: RecurrenceType.solarTerm,
          termLongitude: 0, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 昼夜等长'),
      const Festival(id: 'term_15', name: '清明', recurrence: RecurrenceType.solarTerm,
          termLongitude: 15, category: FestivalCategory.term, defaultAdvanceDays: 3,
          note: '二十四节气 · 扫墓祭祖（另有专项模板）'),
      const Festival(id: 'term_30', name: '谷雨', recurrence: RecurrenceType.solarTerm,
          termLongitude: 30, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_45', name: '立夏', recurrence: RecurrenceType.solarTerm,
          termLongitude: 45, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 夏季开始'),
      const Festival(id: 'term_60', name: '小满', recurrence: RecurrenceType.solarTerm,
          termLongitude: 60, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_75', name: '芒种', recurrence: RecurrenceType.solarTerm,
          termLongitude: 75, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_90', name: '夏至', recurrence: RecurrenceType.solarTerm,
          termLongitude: 90, category: FestivalCategory.term, defaultAdvanceDays: 3,
          note: '二十四节气 · 白昼最长'),
      const Festival(id: 'term_105', name: '小暑', recurrence: RecurrenceType.solarTerm,
          termLongitude: 105, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_120', name: '大暑', recurrence: RecurrenceType.solarTerm,
          termLongitude: 120, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 一年最热'),
      const Festival(id: 'term_135', name: '立秋', recurrence: RecurrenceType.solarTerm,
          termLongitude: 135, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 秋季开始'),
      const Festival(id: 'term_150', name: '处暑', recurrence: RecurrenceType.solarTerm,
          termLongitude: 150, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_165', name: '白露', recurrence: RecurrenceType.solarTerm,
          termLongitude: 165, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_180', name: '秋分', recurrence: RecurrenceType.solarTerm,
          termLongitude: 180, category: FestivalCategory.term, defaultAdvanceDays: 3,
          note: '二十四节气 · 昼夜等长'),
      const Festival(id: 'term_195', name: '寒露', recurrence: RecurrenceType.solarTerm,
          termLongitude: 195, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_210', name: '霜降', recurrence: RecurrenceType.solarTerm,
          termLongitude: 210, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_225', name: '立冬', recurrence: RecurrenceType.solarTerm,
          termLongitude: 225, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 冬季开始'),
      const Festival(id: 'term_240', name: '小雪', recurrence: RecurrenceType.solarTerm,
          termLongitude: 240, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_255', name: '大雪', recurrence: RecurrenceType.solarTerm,
          termLongitude: 255, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_270', name: '冬至', recurrence: RecurrenceType.solarTerm,
          termLongitude: 270, category: FestivalCategory.term, defaultAdvanceDays: 1,
          note: '二十四节气 · 白昼最短（另有专项模板）'),
      const Festival(id: 'term_285', name: '小寒', recurrence: RecurrenceType.solarTerm,
          termLongitude: 285, category: FestivalCategory.term, defaultAdvanceDays: 1),
      const Festival(id: 'term_300', name: '大寒', recurrence: RecurrenceType.solarTerm,
          termLongitude: 300, category: FestivalCategory.term, defaultAdvanceDays: 1),
    ];
  }
}

// ============================================================
// 4 套预设模板
// ============================================================

class Templates {
  Templates._();

  /// ① 传统节日 —— 最常用，中秋端午清明冬至等
  static const traditional = FestivalTemplate(
    id: 'traditional',
    name: '传统节日',
    description: '中秋、端午、清明、冬至等主要传统节日。适合大多数人。',
    festivalIds: [
      'spring_festival', 'yuanxiao', 'duanwu', 'qixi', 'mid_autumn',
      'chongyang', 'qingming', 'winter_solstice', 'zhongyuan', 'laba',
      'xiaonian', 'chuxi', 'hantuo', 'hanshi',
    ],
  );

  /// ② 传统民俗（潮汕/客家）—— 适合年纪较大、有初一十五拜神习惯的用户
  static const folk = FestivalTemplate(
    id: 'folk',
    name: '传统民俗',
    description: '在传统节日基础上，加初一、十五、廿三、廿六拜神祭祀。适合家中保留传统习俗的用户。',
    festivalIds: [
      // 岁时节日
      'spring_festival', 'yuanxiao', 'longtaitou', 'duanwu', 'qixi',
      'mid_autumn', 'chongyang', 'zhongyuan', 'laba', 'xiaonian', 'chuxi',
      // 祭祖
      'qingming', 'winter_solstice', 'hantuo', 'hanshi', 'xiayuan',
      // 拜神（初一十五廿三廿六）
      'chu_yi', 'shi_wu', 'jizao', 'benyue_26', 'weiya',
    ],
  );

  /// ③ 极简 —— 只保留 4 大节日，通知最少
  static const minimal = FestivalTemplate(
    id: 'minimal',
    name: '极简',
    description: '只保留中秋、端午、清明、冬至四个。几乎不被打扰。',
    festivalIds: ['mid_autumn', 'duanwu', 'qingming', 'winter_solstice'],
  );

  /// ④ 全量 —— 所有节日 + 全部二十四节气
  static const everything = FestivalTemplate(
    id: 'everything',
    name: '全量',
    description: '所有传统节日、祭祖日、拜神日，加上全部二十四节气。通知较多。',
    festivalIds: [
      // 岁时节日
      'spring_festival', 'yuanxiao', 'longtaitou', 'duanwu', 'qixi',
      'zhongyuan', 'mid_autumn', 'chongyang', 'laba', 'xiaonian', 'chuxi',
      // 祭祖
      'qingming', 'winter_solstice', 'hantuo', 'hanshi', 'xiayuan',
      // 拜神（农历每月）
      'chu_yi', 'shi_wu', 'jizao', 'weiya', 'benyue_26',
      // 二十四节气（全部 24 个）
      'term_315', 'term_330', 'term_345', 'term_0', 'term_15', 'term_30',
      'term_45', 'term_60', 'term_75', 'term_90', 'term_105', 'term_120',
      'term_135', 'term_150', 'term_165', 'term_180', 'term_195', 'term_210',
      'term_225', 'term_240', 'term_255', 'term_270', 'term_285', 'term_300',
    ],
  );

  static const all = [traditional, folk, minimal, everything];

  static FestivalTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 解析模板中的节日列表（含节气）
  static List<Festival> resolve(FestivalTemplate t) {
    final result = <Festival>[];
    for (final id in t.festivalIds) {
      final f = Festivals.byId(id);
      if (f != null) {
        result.add(f);
      } else if (id.startsWith('term_')) {
        final term = Festivals.allTerms().where((e) => e.id == id);
        if (term.isNotEmpty) result.add(term.first);
      }
    }
    return result;
  }
}

// ============================================================
// 用户选择状态
// ============================================================

/// 节日选择状态（对应「哪些日子要过」）
class FestivalSelection {
  /// 选中的节日 id → 提前提醒天数（null 表示用默认）
  final Map<String, int?> enabled;

  /// 构造默认状态
  FestivalSelection(Map<String, int?> enabled) : enabled = Map.from(enabled);

  /// 从模板创建
  factory FestivalSelection.fromTemplate(FestivalTemplate t) {
    final map = <String, int?>{};
    for (final f in Templates.resolve(t)) {
      map[f.id] = null; // null = 用默认提前量
    }
    return FestivalSelection(map);
  }

  /// 空选择（默认什么都不提醒）
  factory FestivalSelection.empty() => FestivalSelection({});

  /// 默认：传统节日
  factory FestivalSelection.defaultSelection() =>
      FestivalSelection.fromTemplate(Templates.traditional);

  bool isEnabled(String id) => enabled.containsKey(id);

  void setEnabled(Festival f, bool on) {
    if (on) {
      enabled[f.id] = null;
    } else {
      enabled.remove(f.id);
    }
  }

  void toggle(Festival f) {
    if (isEnabled(f.id)) {
      enabled.remove(f.id);
    } else {
      enabled[f.id] = null;
    }
  }

  int advanceDaysOf(Festival f) => enabled[f.id] ?? f.defaultAdvanceDays;

  void setAdvanceDays(String id, int? days) {
    if (enabled.containsKey(id)) {
      enabled[id] = days;
    }
  }

  /// 全部关闭
  void disableAll() => enabled.clear();

  /// 返回一份「切换了 [id]」的新选择 —— 供 UI 侧不可变更新使用
  FestivalSelection withToggled(String id, bool on) {
    final map = Map<String, int?>.from(enabled);
    if (on) {
      map[id] = map[id]; // null 表示用默认提前量
    } else {
      map.remove(id);
    }
    return FestivalSelection(map);
  }

  /// 全部开启（传入可选节日全集）
  void enableAll(List<Festival> list) {
    enabled.clear();
    for (final f in list) {
      enabled[f.id] = null;
    }
  }

  int get enabledCount => enabled.length;
}
