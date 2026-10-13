/// 岁忆 · 节日选择界面
///
/// 这是 App 的核心设置页：用户在这里决定「重视什么日子、需要过什么日子」，
/// 只有勾选的日子才会收到推送，未勾选的完全忽略。
///
/// v1.4.0 新增「自定义」分类：用户可自己添加生日、纪念日等日子。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/festival/festival.dart';
import '../../core/theme.dart';
import '../custom_festival/domain/custom_festival.dart';
import '../custom_festival/presentation/custom_festival_edit_page.dart';
import '../custom_festival/presentation/custom_festival_list_page.dart';
import '../log/service/log_service.dart';
import '../record/presentation/record_providers.dart';

/// 筛选项：自定义用单独的标记（内置 5 类都在 [FestivalCategory] 里）
const String _kCustomFilter = '__custom__';

class FestivalSelectionPage extends ConsumerStatefulWidget {
  final FestivalSelection selection;
  final ValueChanged<FestivalSelection> onChanged;

  const FestivalSelectionPage({
    super.key,
    required this.selection,
    required this.onChanged,
  });

  @override
  ConsumerState<FestivalSelectionPage> createState() => _FestivalSelectionPageState();
}

class _FestivalSelectionPageState extends ConsumerState<FestivalSelectionPage> {
  late FestivalSelection _sel;

  /// null = 全部；[FestivalCategory.x] = 内置分类；[_kCustomFilter] = 自定义
  Object? _filter;

  @override
  void initState() {
    super.initState();
    _sel = FestivalSelection.empty();
    _sel.enabled.addAll(widget.selection.enabled);
  }

  void _update() => widget.onChanged(_sel);

  bool get _showingCustom => _filter == _kCustomFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择你在意的日子'),
        actions: [
          TextButton(
            onPressed: () => _showTemplatePicker(context),
            child: const Text('模板'),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(context),
          _buildFilterBar(context),
          Expanded(child: _showingCustom ? _buildCustomList(context) : _buildList(context)),
        ],
      ),
    );
  }

  // ---------- 头部：已选数量 + 快速操作 ----------
  Widget _buildHeader(BuildContext context) {
    final customs = ref.watch(customFestivalsProvider).valueOrNull ?? const <CustomFestival>[];
    final total = Festivals.all.length + Festivals.allTerms().length + customs.length;
    final count = _sel.enabledCount;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '已选 $count / $total 个日子',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: SuiyaColors.ink,
                ),
              ),
              const Spacer(),
              if (count > 0)
                TextButton(
                  onPressed: () {
                    setState(() => _sel.disableAll());
                    _update();
                  },
                  child: const Text('全部关闭'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count == 0
                ? '当前不会收到任何提醒。只有勾选的日子才会推送。'
                : '只有勾选的日子会收到提醒，未勾选的完全忽略。',
            style: const TextStyle(fontSize: 13, color: SuiyaColors.inkFaint),
          ),
        ],
      ),
    );
  }

  // ---------- 分类筛选（新增「自定义」）----------
  Widget _buildFilterBar(BuildContext context) {
    const categories = <(Object?, String)>[
      (null, '全部'),
      (FestivalCategory.seasonal, '岁时节日'),
      (FestivalCategory.memorial, '祭祖扫墓'),
      (FestivalCategory.worship, '拜神祭祀'),
      (FestivalCategory.term, '二十四节气'),
      (_kCustomFilter, '自定义'),
    ];
    final customs = ref.watch(customFestivalsProvider).valueOrNull ?? const <CustomFestival>[];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final (value, label) in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(
                  label == '自定义' ? '自定义 ${customs.length}' : label,
                  style: TextStyle(
                    fontSize: value == _kCustomFilter ? 13 : null,
                    fontWeight: value == _kCustomFilter ? FontWeight.w500 : null,
                    color: value == _kCustomFilter ? SuiyaColors.cinnabar : null,
                  ),
                ),
                selected: _filter == value,
                onSelected: (s) => setState(() => _filter = s ? value : null),
                selectedColor: SuiyaColors.cinnabar.withOpacity(0.12),
                checkmarkColor: SuiyaColors.cinnabar,
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 内置节日列表 ----------
  Widget _buildList(BuildContext context) {
    final groups = <({String title, List<Festival> items})>[];

    if (_filter == null || _filter == FestivalCategory.seasonal) {
      groups.add((
        title: '岁时节日',
        items: Festivals.byCategory(FestivalCategory.seasonal),
      ));
    }
    if (_filter == null || _filter == FestivalCategory.memorial) {
      groups.add((
        title: '祭祖扫墓',
        items: Festivals.byCategory(FestivalCategory.memorial),
      ));
    }
    if (_filter == null || _filter == FestivalCategory.worship) {
      groups.add((
        title: '拜神祭祀 · 农历每月',
        items: Festivals.byCategory(FestivalCategory.worship),
      ));
    }
    if (_filter == null || _filter == FestivalCategory.term) {
      groups.add((title: '二十四节气', items: Festivals.allTerms()));
    }

    // 「全部」时把自定义节日也带上（可展开的独立入口）
    final showCustomEntry = _filter == null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
      children: [
        if (showCustomEntry) _customEntry(context),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              g.title,
              style: const TextStyle(
                fontSize: 13,
                color: SuiyaColors.inkFaint,
                letterSpacing: 1,
              ),
            ),
          ),
          for (final f in g.items) _buildTile(context, f),
        ],
      ],
    );
  }

  /// 「全部」视图里的自定义入口卡片
  Widget _customEntry(BuildContext context) {
    final customs = ref.watch(customFestivalsProvider).valueOrNull ?? const <CustomFestival>[];
    final enabledCount =
        customs.where((c) => _sel.isEnabled(c.id)).length;
    return InkWell(
      onTap: () => setState(() => _filter = _kCustomFilter),
      borderRadius: BorderRadius.circular(12),
      child: Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SuiyaColors.cinnabar.withOpacity(0.10),
            SuiyaColors.paperDeep
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SuiyaColors.cinnabar.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline,
              size: 22, color: SuiyaColors.cinnabar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('我的自定义日子',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: SuiyaColors.ink)),
                const SizedBox(height: 3),
                Text(
                  customs.isEmpty
                      ? '生日、结婚纪念日、开学日…自己加'
                      : '共 ${customs.length} 个 · 已勾选 $enabledCount 个',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: SuiyaColors.inkFaint),
        ],
      ),
      ),
    );
  }

  // ---------- 自定义节日列表 ----------
  Widget _buildCustomList(BuildContext context) {
    final async = ref.watch(customFestivalsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('自定义日子读取失败：$e',
              style: const TextStyle(color: SuiyaColors.cinnabar)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_calendar_outlined,
                      size: 48, color: SuiyaColors.inkFaint),
                  const SizedBox(height: 16),
                  const Text('还没有自定义的日子',
                      style: TextStyle(fontSize: 16, color: SuiyaColors.ink)),
                  const SizedBox(height: 8),
                  const Text('生日、结婚纪念日、开学日、家里忌日……\n都可以按公历或农历加进来',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SuiyaColors.inkFaint)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _createCustom(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建一个日子'),
                    style: FilledButton.styleFrom(backgroundColor: SuiyaColors.cinnabar),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                '共 ${list.length} 个 · 点一下勾选，长按可改',
                style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
              ),
            ),
            for (final c in list) _buildCustomTile(context, c),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                onPressed: () => _createCustom(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('再添加一个'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SuiyaColors.cinnabar,
                  side: BorderSide(color: SuiyaColors.cinnabar.withOpacity(0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCustomTile(BuildContext context, CustomFestival c) {
    final on = _sel.isEnabled(c.id);
    final f = c.asFestival();
    return InkWell(
      onTap: () {
        setState(() {
          if (on) {
            _sel.enabled.remove(c.id);
          } else {
            _sel.enabled[c.id] = null;
          }
        });
        _update();
      },
      onLongPress: () => _editCustom(context, c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: on ? SuiyaColors.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: SuiyaColors.ink.withOpacity(0.06)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? SuiyaColors.cinnabar : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? SuiyaColors.cinnabar : SuiyaColors.inkFaint,
                  width: 1.4,
                ),
              ),
              child: on
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(c.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: on ? SuiyaColors.ink : SuiyaColors.inkSoft,
                          )),
                      const SizedBox(width: 6),
                      _miniTag(c.recurrence == CustomRecurrence.solarOnce
                          ? '仅此一次'
                          : '每年'),
                    ],
                  ),
                  if (f.note != null) ...[
                    const SizedBox(height: 2),
                    Text(f.note!,
                        style: const TextStyle(
                            fontSize: 12, color: SuiyaColors.inkFaint)),
                  ],
                ],
              ),
            ),
            if (on)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(c.nextLabel(),
                      style: const TextStyle(
                          fontSize: 12, color: SuiyaColors.inkFaint)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _showAdvanceDaysSheet(context, f),
                    child: Text('提前 ${_sel.advanceDaysOf(f)} 天',
                        style: const TextStyle(
                            fontSize: 12, color: SuiyaColors.cinnabar)),
                  ),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 17),
              color: SuiyaColors.inkFaint,
              onPressed: () => _editCustom(context, c),
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCustom(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CustomFestivalEditPage()),
    );
    if (saved == true && mounted) {
      LogService.info('自定义', '新建自定义日子');
      ref.invalidate(customFestivalsProvider);
      _reloadSelection();
    }
  }

  Future<void> _editCustom(BuildContext context, CustomFestival c) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => CustomFestivalEditPage(existing: c)),
    );
    if (saved == true && mounted) {
      ref.invalidate(customFestivalsProvider);
      _reloadSelection();
    }
  }

  /// 从 provider 重新同步勾选状态（自定义节日保存后会自动勾上）
  void _reloadSelection() {
    final next = ref.read(selectionProvider);
    setState(() {
      // 必须以空选择为底：用传统模板全集打底的话，addAll 不会移除
      // 多余的键，用户「全部关闭」的状态会被静默覆盖回全集
      _sel = FestivalSelection.empty();
      _sel.enabled.addAll(next.enabled);
    });
  }

  /// 管理全部自定义日子（另一个入口）
  Future<void> _manageCustom(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomFestivalListPage()),
    );
    if (mounted) {
      ref.invalidate(customFestivalsProvider);
      _reloadSelection();
    }
  }

  // ---------- 内置节日行 ----------
  Widget _buildTile(BuildContext context, Festival f) {
    final on = _sel.isEnabled(f.id);
    final next = _nextOccurrenceLabel(f);

    return InkWell(
      onTap: () {
        setState(() => _sel.toggle(f));
        _update();
      },
      onLongPress: on ? () => _showAdvanceDaysSheet(context, f) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: on ? SuiyaColors.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: SuiyaColors.ink.withOpacity(0.06)),
          ),
        ),
        child: Row(
          children: [
            // 复选框
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? SuiyaColors.cinnabar : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? SuiyaColors.cinnabar : SuiyaColors.inkFaint,
                  width: 1.4,
                ),
              ),
              child: on
                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        f.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: on ? SuiyaColors.ink : SuiyaColors.inkSoft,
                        ),
                      ),
                      if (f.recurrence == RecurrenceType.lunarMonthly) ...[
                        const SizedBox(width: 6),
                        const Text(
                          '每月',
                          style: TextStyle(fontSize: 11, color: SuiyaColors.ochre),
                        ),
                      ],
                    ],
                  ),
                  if (f.note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      f.note!,
                      style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
            if (on)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    next,
                    style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: () => _showAdvanceDaysSheet(context, f),
                    child: Text(
                      '提前 ${_sel.advanceDaysOf(f)} 天',
                      style: const TextStyle(fontSize: 12, color: SuiyaColors.cinnabar),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniTag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: SuiyaColors.cinnabar.withOpacity(0.10),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(t,
            style: const TextStyle(fontSize: 10, color: SuiyaColors.cinnabar)),
      );

  // ---------- 工具方法 ----------

  String _nextOccurrenceLabel(Festival f) {
    final now = DateTime.now();
    final next = f.nextOccurrence(now);
    if (next == null) return '';
    final days = DateTime(next.year, next.month, next.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final md = '${next.month}/${next.day}';
    if (days == 0) return '就是今天';
    return '$md · 还有 $days 天';
  }

  // ---------- 模板选择 ----------
  void _showTemplatePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SuiyaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '选择一套模板',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '套用后仍可自由增减',
                style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
              ),
            ),
            for (final t in Templates.all)
              ListTile(
                title: Text(t.name, style: const TextStyle(fontSize: 15)),
                subtitle: Text(
                  t.description,
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
                ),
                onTap: () {
                  setState(() {
                    // 保留自定义日子的勾选，不被模板覆盖掉
                    final customPicked = {
                      for (final e in _sel.enabled.entries)
                        if (e.key.startsWith('custom_')) e.key: e.value
                    };
                    _sel = FestivalSelection.fromTemplate(t);
                    _sel.enabled.addAll(customPicked);
                  });
                  _update();
                  Navigator.pop(ctx);
                },
              ),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: SuiyaColors.cinnabar),
              title: const Text('自定义栏目',
                  style: TextStyle(fontSize: 15, color: SuiyaColors.cinnabar)),
              subtitle: const Text('管理我自己的日子',
                  style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
              onTap: () {
                Navigator.pop(ctx);
                _manageCustom(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------- 提前天数设置 ----------
  void _showAdvanceDaysSheet(BuildContext context, Festival f) {
    const options = [0, 1, 2, 3, 5, 7, 15, 30];
    final current = _sel.advanceDaysOf(f);
    showModalBottomSheet(
      context: context,
      backgroundColor: SuiyaColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                '${f.name} · 提前几天提醒',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                f.defaultAdvanceDays == current
                    ? '默认 ${f.defaultAdvanceDays} 天'
                    : '已自定义（默认 ${f.defaultAdvanceDays} 天）',
                style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in options)
                  ChoiceChip(
                    label: Text(d == 0 ? '当天' : '$d 天'),
                    selected: current == d,
                    onSelected: (_) {
                      setState(() => _sel.setAdvanceDays(f.id, d));
                      _update();
                      Navigator.pop(ctx);
                    },
                    selectedColor: SuiyaColors.cinnabar.withOpacity(0.12),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}