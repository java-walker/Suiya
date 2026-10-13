/// 岁忆 · 可旋转展开的预设选择器
///
/// 取代原来的「一行横线输入框」：
///   收起态  → 只有一个按钮，显示「同行的人（已选 3）」+ 一个会旋转的箭头
///   展开态  → 箭头旋转 90°，露出预设勾选项网格 + 「添加」按钮
///
/// 添加弹窗里带「保存为预设」开关 —— 勾上则下次直接勾选。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../preset/data/preset_store.dart';
import 'record_providers.dart';

/// 一个可旋转展开的多选面板
class PresetPicker extends ConsumerStatefulWidget {
  /// 预设类别（人 / 标签）
  final PresetKind kind;

  /// 当前已选项
  final List<String> selected;

  /// 变更回调
  final ValueChanged<List<String>> onChanged;

  final IconData icon;

  const PresetPicker({
    super.key,
    required this.kind,
    required this.selected,
    required this.onChanged,
    required this.icon,
  });

  @override
  ConsumerState<PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends ConsumerState<PresetPicker> {
  bool _expanded = false;
  bool _seeded = false;

  /// 首次展开且数据库为空时，把内置预设灌进去
  Future<void> _ensureSeeded(List<Preset> presets) async {
    if (_seeded || presets.isNotEmpty) return;
    _seeded = true;
    final defaults =
        widget.kind == PresetKind.people ? builtinPeoplePresets : builtinTagPresets;
    final actions = ref.read(presetActionsProvider);
    for (final d in defaults) {
      await actions.add(widget.kind, d);
    }
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final result = await showDialog<_AddResult>(
      context: context,
      builder: (_) => _AddDialog(kind: widget.kind),
    );
    if (result == null || !mounted) return;

    // 勾上（去重，避免重复添加）
    final next = [...widget.selected];
    for (final n in result.items) {
      if (!next.contains(n)) next.add(n);
    }
    widget.onChanged(next);

    // 是否存为预设
    if (result.saveAsPreset) {
      final actions = ref.read(presetActionsProvider);
      for (final n in result.items) {
        await actions.add(widget.kind, n);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _removePreset(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: const Text('删除这个预设？', style: TextStyle(fontSize: 16)),
        content: Text('「$name」会从预设里移除，\n已经用过的记录不受影响。',
            style: const TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除', style: TextStyle(color: SuiyaColors.cinnabar))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(presetActionsProvider).remove(widget.kind, name);
    if (mounted) setState(() {});
  }

  void _toggle(String name) {
    final next = [...widget.selected];
    if (next.contains(name)) {
      next.remove(name);
    } else {
      next.add(name);
    }
    widget.onChanged(next);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(presetsProvider(widget.kind));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== 收起态：单个按钮 + 可旋转箭头 =====
        Material(
          color: SuiyaColors.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.selected.isEmpty
                      ? SuiyaColors.paperDeep
                      : SuiyaColors.cinnabar.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(widget.icon,
                      size: 17,
                      color: widget.selected.isEmpty
                          ? SuiyaColors.inkFaint
                          : SuiyaColors.cinnabar),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.kind.label,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.selected.isEmpty
                            ? SuiyaColors.inkSoft
                            : SuiyaColors.ink,
                        fontWeight:
                            widget.selected.isEmpty ? FontWeight.normal : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.selected.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: SuiyaColors.cinnabar.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('${widget.selected.length}',
                          style: const TextStyle(
                              fontSize: 11, color: SuiyaColors.cinnabar)),
                    ),
                  const SizedBox(width: 6),
                  // 展开时旋转 90°
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.chevron_right,
                        size: 20, color: SuiyaColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ===== 已选项摘要（收起时也可见）=====
        if (!_expanded && widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in widget.selected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: SuiyaColors.paperDeep,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(s,
                        style: const TextStyle(
                            fontSize: 11, color: SuiyaColors.inkSoft)),
                  ),
              ],
            ),
          ),

        // ===== 展开态：预设勾选 + 添加 =====
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  decoration: BoxDecoration(
                    color: SuiyaColors.paperDeep.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: presetsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('预设读取失败：$e',
                          style: const TextStyle(fontSize: 12, color: SuiyaColors.cinnabar)),
                    ),
                    data: (presets) {
                      _ensureSeeded(presets);
                      if (presets.isEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('还没有预设，点下面「添加」建一个',
                                style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
                            const SizedBox(height: 10),
                            _addButton(),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '预设 · 勾选后自动填入',
                            style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in presets)
                                _PresetChip(
                                  name: p.name,
                                  selected: widget.selected.contains(p.name),
                                  onTap: () => _toggle(p.name),
                                  onLongPress: () => _removePreset(p.name),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _addButton(),
                        ],
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _addButton() => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 16),
          label: Text('添加${widget.kind.label}', style: const TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: SuiyaColors.cinnabar,
            side: BorderSide(color: SuiyaColors.cinnabar.withOpacity(0.3)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
}

/// 预设勾选项
class _PresetChip extends StatelessWidget {
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PresetChip({
    required this.name,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: FilterChip(
        label: Text(name, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: SuiyaColors.cinnabar.withOpacity(0.14),
        checkmarkColor: SuiyaColors.cinnabar,
        backgroundColor: SuiyaColors.surface,
        side: BorderSide(
          color: selected
              ? SuiyaColors.cinnabar.withOpacity(0.4)
              : SuiyaColors.paperDeep,
        ),
        showCheckmark: true,
      ),
    );
  }
}

/// 添加弹窗返回结果
class _AddResult {
  final String name;
  final bool saveAsPreset;

  /// 实际要添加的项（多人模式下可能多于一个）
  final List<String> items;

  const _AddResult(this.name, this.saveAsPreset, this.items);
}

/// 添加自定义项的弹窗
class _AddDialog extends StatefulWidget {
  final PresetKind kind;
  const _AddDialog({required this.kind});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _ctl = TextEditingController();
  bool _saveAsPreset = true;
  bool _multiple = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// 提交：多人模式下按分隔符拆成多个
  _AddResult? _submit() {
    final raw = _ctl.text.trim();
    if (raw.isEmpty) return null;
    if (_multiple) {
      final names = raw
          .split(RegExp(r'[、,，\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (names.isEmpty) return null;
      return _AddResult(names.join(' '), _saveAsPreset, names);
    }
    return _AddResult(raw, _saveAsPreset, [raw]);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _ctl.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: SuiyaColors.surface,
      title: Text('添加${widget.kind.label}',
          style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctl,
            autofocus: true,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: widget.kind == PresetKind.people ? '如：外公、二姨' : '如：祭扫、远路',
              isDense: true,
              filled: true,
              fillColor: SuiyaColors.paperDeep,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.kind == PresetKind.people) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _multiple,
              onChanged: (v) => setState(() => _multiple = v ?? false),
              title: const Text('一次添加多个',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text('用「、」或逗号分隔',
                  style: TextStyle(fontSize: 11)),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          const Divider(height: 20),
          // 关键需求：添加时可选是否保存为预设
          SwitchListTile(
            value: _saveAsPreset,
            onChanged: (v) => setState(() => _saveAsPreset = v),
            title: const Text('保存为预设', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              _saveAsPreset
                  ? '下次可直接勾选（长按预设可删除）'
                  : '仅本次使用，不进入预设列表',
              style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        TextButton(
          onPressed: canSubmit ? () => Navigator.of(context).pop(_submit()) : null,
          child: const Text('添加'),
        ),
      ],
    );
  }
}