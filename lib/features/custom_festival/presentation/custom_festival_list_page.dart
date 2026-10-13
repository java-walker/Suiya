/// 岁忆 · 自定义日子列表页
///
/// 从「模板页 → 自定义」进入，管理用户自己定义的日子。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../record/presentation/record_providers.dart';
import '../domain/custom_festival.dart';
import 'custom_festival_edit_page.dart';

class CustomFestivalListPage extends ConsumerWidget {
  const CustomFestivalListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customFestivalsProvider);
    final selection = ref.watch(selectionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的自定义日子')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SuiyaColors.cinnabar,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新建', style: TextStyle(color: Colors.white)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('加载失败：$e',
                style: const TextStyle(color: SuiyaColors.inkSoft)),
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
                    const Text('生日、结婚纪念日、开学日、家里忌日……\n都可以自己加进来',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: SuiyaColors.inkFaint)),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final f in list)
                _Tile(
                  item: f,
                  enabled: selection.isEnabled(f.id),
                  onTap: () => _edit(context, ref, f),
                  onToggle: (on) async {
                    await ref
                        .read(selectionProvider.notifier)
                        .update(selection.withToggled(f.id, on));
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, CustomFestival? existing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomFestivalEditPage(existing: existing),
      ),
    );
    ref.invalidate(customFestivalsProvider);
  }
}

class _Tile extends StatelessWidget {
  final CustomFestival item;
  final bool enabled;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _Tile({
    required this.item,
    required this.enabled,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Checkbox(
              value: enabled,
              activeColor: SuiyaColors.cinnabar,
              onChanged: (v) => onToggle(v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(item.name,
                          style: const TextStyle(
                              fontSize: 15, color: SuiyaColors.ink)),
                      const SizedBox(width: 8),
                      _pill(item.recurrence == CustomRecurrence.solarOnce
                          ? '仅此一次'
                          : '每年'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.nextLabel(),
                    style: const TextStyle(
                        fontSize: 12, color: SuiyaColors.inkFaint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: SuiyaColors.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: SuiyaColors.paperDeep,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(t,
            style: const TextStyle(fontSize: 10, color: SuiyaColors.inkFaint)),
      );
}