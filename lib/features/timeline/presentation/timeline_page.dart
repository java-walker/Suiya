/// 岁忆 · 岁时时间轴（首页）
///
/// 四个状态对应需求 F2：已记录 / 将至 / 待记录（唤回钩子）/ 普通
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/lunar/lunar_engine.dart';
import '../../../core/theme.dart';
import '../../log/service/log_service.dart';
import '../../place/presentation/map_launcher.dart';
import '../../record/data/media_store.dart';
import '../../record/domain/memory_record.dart';
import '../../record/presentation/record_providers.dart';

class TimelinePage extends ConsumerStatefulWidget {
  const TimelinePage({super.key});

  @override
  ConsumerState<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends ConsumerState<TimelinePage> {
  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final async = ref.watch(timelineProvider(year));

    return Scaffold(
      appBar: AppBar(
        title: const Text('岁忆'),
        actions: [
          // v1.3.0 的 bug：两个按钮都指向 /settings，而 /settings 又被
          // 错误地绑定到模板页 —— 结果点「设置」进的是模板。现在各归各位。
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/festival-selection'),
            tooltip: '选择日子',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: '设置',
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => _errorView(e),
        data: (items) {
          if (items.isEmpty) return const _emptyView();
          final upcoming =
              items.where((i) => i.daysUntil >= 0).toList(growable: false);
          final next = upcoming.isEmpty ? null : upcoming.first;
          final missed =
              items.where((i) => i.status == NodeStatus.missed).toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
            children: [
              if (next != null) _NextCard(item: next),
              _ReminderPreview(),
              if (missed.isNotEmpty) _missedHint(missed),
              _yearHeader(year),
              for (final i in items) _Node(item: i),
            ],
          );
        },
      ),
    );
  }

  Widget _errorView(Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('加载失败：$e',
              style: const TextStyle(color: SuiyaColors.inkSoft)),
        ),
      );

  Widget _yearHeader(int year) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Row(
          children: [
            Text('$year 年',
                style: const TextStyle(
                    fontSize: 13, color: SuiyaColors.inkFaint, letterSpacing: 1)),
            const SizedBox(width: 12),
            const Expanded(child: Divider()),
          ],
        ),
      );

  /// 「有 N 个日子过了还没记」——这是重要的唤回钩子
  Widget _missedHint(List<TimelineItem> missed) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: SuiyaColors.paperDeep,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_calendar, size: 16, color: SuiyaColors.inkSoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${missed.length} 个日子已经过了，还没写下点什么',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft)),
            ),
          ],
        ),
      );
}

/// 「下一个日子」大卡片
class _NextCard extends ConsumerWidget {
  final TimelineItem item;
  const _NextCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = item.festival;
    final lunar =
        LunarEngine.solarToLunar(item.date.year, item.date.month, item.date.day);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SuiyaColors.cinnabar.withOpacity(0.10), SuiyaColors.paperDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SuiyaColors.cinnabar.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('下一个日子',
                  style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
              const Spacer(),
              Text('${item.date.month}月${item.date.day}日',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft)),
            ],
          ),
          const SizedBox(height: 6),
          Text(f.name,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w500,
                color: SuiyaColors.ink,
                letterSpacing: 2,
              )),
          Text('农历${lunar.month}月${lunar.day}日',
              style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (item.isToday)
                const Text('就是今天',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: SuiyaColors.cinnabar))
              else ...[
                Text('${item.daysUntil}',
                    style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w500,
                        color: SuiyaColors.cinnabar,
                        height: 1.1)),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 6),
                  child: Text('天后',
                      style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
                ),
              ],
              const Spacer(),
              if (item.hasRecord)
                OutlinedButton.icon(
                  onPressed: () => _openDetail(context, ref, item),
                  icon: const Icon(Icons.check_circle, size: 16, color: SuiyaColors.moss),
                  label: const Text('已记下'),
                )
              else
                FilledButton(
                  onPressed: () => _createRecord(context, ref, item),
                  style: FilledButton.styleFrom(
                    backgroundColor: SuiyaColors.cinnabar,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('去记录'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间轴上的一个节点
class _Node extends ConsumerWidget {
  final TimelineItem item;
  const _Node({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = item.festival;
    final lunar =
        LunarEngine.solarToLunar(item.date.year, item.date.month, item.date.day);
    final past = item.isPast;
    final dotColor = item.hasRecord
        ? SuiyaColors.moss
        : item.status == NodeStatus.missed
            ? SuiyaColors.inkFaint.withOpacity(0.4)
            : SuiyaColors.cinnabar;

    return InkWell(
      onTap: () => item.hasRecord
          ? _openDetail(context, ref, item)
          : _createRecord(context, ref, item),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间轴竖线 + 圆点（固定高度，勿用 IntrinsicHeight+Expanded，会死循环）
            SizedBox(
              width: 18,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 1, height: 8, color: SuiyaColors.ink.withOpacity(0.12)),
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: dotColor),
                  ),
                  Container(width: 1, height: 30, color: SuiyaColors.ink.withOpacity(0.12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 日期
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${item.date.month}/${item.date.day}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: past ? SuiyaColors.inkFaint : SuiyaColors.ink,
                      )),
                  Text('农历${lunar.month}月${lunar.day}日',
                      style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 名称 + 状态
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name,
                      style: TextStyle(
                        fontSize: 15,
                        color: past ? SuiyaColors.inkSoft : SuiyaColors.ink,
                      )),
                  if (f.note != null)
                    Text(f.note!,
                        style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
                ],
              ),
            ),
            // 右侧状态
            if (item.hasRecord)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle, size: 18, color: SuiyaColors.moss),
              )
            else if (item.isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: SuiyaColors.cinnabar, borderRadius: BorderRadius.circular(4)),
                child: const Text('今天',
                    style: TextStyle(fontSize: 11, color: Colors.white)),
              )
            else if (past)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: SuiyaColors.paperDeep, borderRadius: BorderRadius.circular(4)),
                child: const Text('待记录',
                    style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
              )
            else
              Text('还有 ${item.daysUntil} 天',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
          ],
        ),
      ),
    );
  }
}

Future<void> _createRecord(BuildContext context, WidgetRef ref, TimelineItem item) async {
  // 用 go_router 而不是裸 MaterialPageRoute：返回时路由栈状态一致，
  // 且编辑页 pop 后 invalidate 的 provider 能立即反映到本页。
  await context.push('/record/new', extra: item.festival);
  if (context.mounted) {
    ref.invalidate(timelineProvider(DateTime.now().year));
  }
}

Future<void> _openDetail(BuildContext context, WidgetRef ref, TimelineItem item) async {
  final rec = item.record;
  if (rec == null) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SuiyaColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _RecordSheet(record: rec),
  );
}

/// 已记录详情
class _RecordSheet extends ConsumerWidget {
  final MemoryRecord record;
  const _RecordSheet({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(record.title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: SuiyaColors.ink)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(record.displayDate,
                style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
            if (record.qa.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final q in record.qa)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(q.question,
                          style: const TextStyle(
                              fontSize: 12,
                              color: SuiyaColors.cinnabar,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text(q.answer,
                          style: const TextStyle(fontSize: 14, color: SuiyaColors.ink)),
                    ],
                  ),
                ),
            ],
            if (record.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(record.text,
                  style: const TextStyle(fontSize: 14, color: SuiyaColors.ink, height: 1.6)),
            ],
            if (record.participants.isNotEmpty) ...[
              const SizedBox(height: 16),
              _meta(Icons.people_outline, '同行：${record.participants.join('、')}'),
            ],
            if (record.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _meta(Icons.local_offer_outlined, '标签：${record.tags.join('、')}'),
            ],
            // v1.4.0：地点可直接导航，不必回编辑页
            if (record.lat != null && record.lng != null) ...[
              const SizedBox(height: 8),
              _metaRow(
                icon: Icons.place_outlined,
                text: record.address ?? '已记录坐标',
                action: OutlinedButton.icon(
                  onPressed: () => _navigateFromSheet(context, record),
                  icon: const Icon(Icons.navigation, size: 14),
                  label: const Text('导航', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SuiyaColors.cinnabar,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
            _RecordPhotos(recordId: record.id),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // 先抓 router 再 pop：pop 之后这个 context 已失效，
                      // 再用它 push 会在 debug 模式断言崩溃
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push('/record/edit', extra: record);
                    },
                    child: const Text('编辑'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(recordActionsProvider)
                          .delete(record.id, record.year);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: SuiyaColors.inkFaint),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: SuiyaColors.inkFaint),
          const SizedBox(width: 6),
          Expanded(
              child:
                  Text(text, style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft))),
        ],
      );

  /// 带右侧按钮的一行（地点导航）
  Widget _metaRow({
    required IconData icon,
    required String text,
    required Widget action,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: SuiyaColors.inkFaint),
          const SizedBox(width: 6),
          Expanded(
              child:
                  Text(text, style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft))),
          action,
        ],
      );
}

/// 从详情弹窗唤起导航
Future<void> _navigateFromSheet(BuildContext context, MemoryRecord record) async {
  final name = record.address ?? record.title;
  final ok = await MapLauncher.navigate(
      lat: record.lat!, lng: record.lng!, name: name);
  if (ok) {
    LogService.info('地点', '已唤起导航', detail: record.title);
  } else {
    LogService.warning('地点', '导航唤起失败', detail: record.title);
  }
  if (!ok && context.mounted) {
    await MapLauncher.copyCoordinates(record.lat!, record.lng!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没有可用的地图应用，坐标已复制')),
    );
  }
}

/// 详情弹窗里的照片区（证明图片确实保存下来了）
class _RecordPhotos extends ConsumerWidget {
  final String recordId;
  const _RecordPhotos({required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaOfProvider(recordId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        final photos = list.where((m) => m.kind == 'photo').toList();
        if (photos.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('照片 ${photos.length} 张',
                style: const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
            const SizedBox(height: 8),
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(MediaStore.absolutePathSync(photos[i].path)),
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 76,
                        height: 76,
                        color: SuiyaColors.paperDeep,
                        child: const Icon(Icons.broken_image,
                            size: 16, color: SuiyaColors.inkFaint),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _emptyView extends StatelessWidget {
  const _emptyView();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.filter_list_off, size: 48, color: SuiyaColors.inkFaint),
              const SizedBox(height: 16),
              const Text('还没有选择任何日子',
                  style: TextStyle(fontSize: 16, color: SuiyaColors.ink)),
              const SizedBox(height: 8),
              const Text('选好你在意的日子，时间轴才会为你展开',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: SuiyaColors.inkFaint)),
            ],
          ),
        ),
      );
}

/// 未来提醒预览：让用户确认"下个清明会提醒我"
class _ReminderPreview extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingRemindersProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        final r = list.first;
        final d = r.solarDate;
        final diff = r.daysUntil;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SuiyaColors.moss.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  size: 16, color: SuiyaColors.moss),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diff == 0
                      ? '今天会提醒你：${r.title}'
                      : '$diff 天后（${d?.month}/${d?.day}）提醒：${r.title}',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft),
                ),
              ),
              if (list.length > 1)
                Text('共 ${list.length} 条',
                    style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
            ],
          ),
        );
      },
    );
  }
}
