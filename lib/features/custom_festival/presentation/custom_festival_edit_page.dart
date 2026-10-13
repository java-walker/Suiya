/// 岁忆 · 自定义日子编辑页
///
/// 用户自己定义「要过的日子」：生日、结婚纪念日、开学日、家里忌日……
/// 支持公历固定日期 / 公历每年 / 农历每年 / 农历每月。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/festival/festival.dart';
import '../../../core/theme.dart';
import '../../log/service/log_service.dart';
import '../../record/presentation/record_providers.dart';
import '../domain/custom_festival.dart';

class CustomFestivalEditPage extends ConsumerStatefulWidget {
  final CustomFestival? existing;

  /// 从模板页「新建」进入时预填的 id（新建后直接勾上）
  final VoidCallback? onSaved;

  const CustomFestivalEditPage({super.key, this.existing, this.onSaved});

  @override
  ConsumerState<CustomFestivalEditPage> createState() =>
      _CustomFestivalEditPageState();
}

class _CustomFestivalEditPageState
    extends ConsumerState<CustomFestivalEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _advance;
  late CustomRecurrence _recurrence;
  int? _solarMonth;
  int? _solarDay;
  int? _lunarMonth;
  int? _lunarDay;
  /// 「仅此一次」的锚定年份
  late int _anchorYear;

  /// 引导提问用 controller 管理：TextFormField 按 position 复用 State、
  /// initialValue 不再生效，removeAt 中间项后看到的第 i 条与保存的
  /// 第 i 条可能不是同一条
  final List<TextEditingController> _promptCtrls = [];
  bool _saving = false;

  bool get _useSolar =>
      _recurrence == CustomRecurrence.solarOnce ||
      _recurrence == CustomRecurrence.solarAnnual;
  bool get _useLunar =>
      _recurrence == CustomRecurrence.lunarAnnual ||
      _recurrence == CustomRecurrence.lunarMonthly;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _advance = TextEditingController(text: '${e?.defaultAdvanceDays ?? 1}');
    _recurrence = e?.recurrence ?? CustomRecurrence.solarAnnual;
    _solarMonth = e?.solarMonth ?? 1;
    _solarDay = e?.solarDay ?? 1;
    _lunarMonth = e?.lunarMonth ?? 1;
    _lunarDay = e?.lunarDay ?? 1;
    _anchorYear = e?.anchorYear ?? DateTime.now().year;
    if (e != null) {
      for (final p in e.prompts) {
        _promptCtrls.add(TextEditingController(text: p.question));
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _advance.dispose();
    for (final c in _promptCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('给这个日子起个名字');
      return;
    }
    if (_useSolar && (_solarMonth == null || _solarDay == null)) {
      _toast('请选择公历月日');
      return;
    }
    if (_useLunar && (_lunarMonth == null || _lunarDay == null)) {
      _toast('请选择农历月日');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = widget.existing;
    final prompts = [
      for (final c in _promptCtrls)
        if (c.text.trim().isNotEmpty) PromptTemplate(c.text.trim())
    ];

    final item = e == null
        ? CustomFestival(
            id: CustomFestival.newId(),
            name: name,
            recurrence: _recurrence,
            solarMonth: _useSolar ? _solarMonth : null,
            solarDay: _useSolar ? _solarDay : null,
            lunarMonth: _useLunar ? _lunarMonth : null,
            lunarDay: _useLunar ? _lunarDay : null,
            defaultAdvanceDays: int.tryParse(_advance.text.trim()) ?? 1,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            prompts: prompts,
            sortIndex: 0,
            anchorYear:
                _recurrence == CustomRecurrence.solarOnce ? _anchorYear : null,
            createdAt: now,
            updatedAt: now,
          )
        : e.copyWith(
            name: name,
            recurrence: _recurrence,
            solarMonth: _useSolar ? _solarMonth : null,
            solarDay: _useSolar ? _solarDay : null,
            lunarMonth: _useLunar ? _lunarMonth : null,
            lunarDay: _useLunar ? _lunarDay : null,
            defaultAdvanceDays: int.tryParse(_advance.text.trim()) ?? 1,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            prompts: prompts,
            anchorYear:
                _recurrence == CustomRecurrence.solarOnce ? _anchorYear : null,
            updatedAt: now,
          );

    try {
      await ref.read(customFestivalActionsProvider).save(item);

      // 新建后自动勾上，省得用户还要去列表里再点一次
      if (e == null) {
        final sel = ref.read(selectionProvider);
        if (!sel.isEnabled(item.id)) {
          final next = FestivalSelection(Map.of(sel.enabled)..[item.id] = null);
          await ref.read(selectionProvider.notifier).update(next);
        }
      }
      if (!mounted) return;
      // 关键：pop 之前先拿 ScaffoldMessenger，pop 之后 context 已失效
      // （record_editor_page 在 v1.4.0 修过同型崩溃，这页漏了）
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text('已保存「$name」')));
      widget.onSaved?.call();
    } catch (err) {
      LogService.exception('自定义', '保存失败', err, null);
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$err');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// 预览：这个日子今年几月几号
  String? _preview() {
    final now = DateTime.now();
    final tmp = CustomFestival(
      id: 'preview',
      name: _name.text.trim().isEmpty ? '这个日子' : _name.text.trim(),
      recurrence: _recurrence,
      solarMonth: _useSolar ? _solarMonth : null,
      solarDay: _useSolar ? _solarDay : null,
      lunarMonth: _useLunar ? _lunarMonth : null,
      lunarDay: _useLunar ? _lunarDay : null,
      anchorYear: _recurrence == CustomRecurrence.solarOnce ? _anchorYear : null,
      createdAt: 0,
      updatedAt: 0,
    );
    // 一次性日子只在自己的锚定年份预览，否则一律按今年算
    final viewYear =
        _recurrence == CustomRecurrence.solarOnce ? _anchorYear : now.year;
    final d = tmp.dateIn(viewYear);
    if (d == null) return null;
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final md = '${d.year} 年 ${d.month} 月 ${d.day} 日';
    if (days == 0) return '$md · 就是今天';
    if (days > 0) return '$md · 还有 $days 天';
    return '$md · 已过 ${-days} 天';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '自定义一个日子' : '编辑'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _label('名称'),
          TextField(
            controller: _name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: '如：母亲生日 / 结婚纪念日',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          _label('按哪种方式重复'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in CustomRecurrence.values)
                ChoiceChip(
                  label: Text(r.label, style: const TextStyle(fontSize: 12)),
                  selected: _recurrence == r,
                  selectedColor: SuiyaColors.cinnabar.withOpacity(0.14),
                  onSelected: (_) => setState(() {
                    _recurrence = r;
                    // 「仅此一次」需要锚定年份，否则无法真正做到只出现一次
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_recurrence.hint,
              style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),

          if (_recurrence == CustomRecurrence.solarOnce) ...[
            const SizedBox(height: 16),
            _label('只在哪一年'),
            _numPicker(
              label: '年',
              value: _anchorYear,
              min: 2000,
              max: 2099,
              onChanged: (v) => setState(() => _anchorYear = v),
            ),
          ],

          const SizedBox(height: 20),
          if (_useSolar) ...[
            _label('公历日期'),
            Row(
              children: [
                Expanded(
                  child: _numPicker(
                    label: '月',
                    value: _solarMonth ?? 1,
                    min: 1,
                    max: 12,
                    onChanged: (v) => setState(() {
                      _solarMonth = v;
                      // 换月后把日钳制到该月实际天数，避免 2 月 30
                      // 被 DateTime 静默归一成 3 月 2 日
                      final dim = _daysInSolarMonth(v);
                      if ((_solarDay ?? 1) > dim) _solarDay = dim;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numPicker(
                    label: '日',
                    value: _solarDay ?? 1,
                    min: 1,
                    max: _daysInSolarMonth(_solarMonth ?? 1),
                    onChanged: (v) => setState(() => _solarDay = v),
                  ),
                ),
              ],
            ),
          ],
          if (_useLunar) ...[
            _label('农历日期'),
            Row(
              children: [
                Expanded(
                  child: _numPicker(
                    label: '月',
                    value: _lunarMonth ?? 1,
                    min: 1,
                    max: 12,
                    onChanged: (v) => setState(() => _lunarMonth = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _numPicker(
                    label: '日',
                    value: _lunarDay ?? 1,
                    min: 1,
                    max: 30,
                    onChanged: (v) => setState(() => _lunarDay = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('农历初一到三十，大小月由年份决定',
                style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
          ],

          const SizedBox(height: 24),
          _label('提前几天提醒'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _advance,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: '1'),
                ),
              ),
              const SizedBox(width: 12),
              const Text('天', style: TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
            ],
          ),

          const SizedBox(height: 24),
          _label('备注'),
          TextField(
            controller: _note,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(hintText: '选填，如：农历八月十五 自家忌日'),
          ),

          const SizedBox(height: 24),
          _label('引导提问'),
          _promptEditor(),

          if (preview != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SuiyaColors.cinnabar.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_outlined,
                      size: 17, color: SuiyaColors.cinnabar),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('今年：$preview',
                        style: const TextStyle(
                            fontSize: 13, color: SuiyaColors.ink)),
                  ),
                ],
              ),
            ),
          ],

          if (widget.existing != null) ...[
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(customFestivalActionsProvider)
                    .delete(widget.existing!.id);
                if (!mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop(true);
                messenger.showSnackBar(
                    const SnackBar(content: Text('已删除')));
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除这个日子'),
              style: OutlinedButton.styleFrom(foregroundColor: SuiyaColors.cinnabar),
            ),
          ],
        ],
      ),
    );
  }

  /// 引导提问编辑
  Widget _promptEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_promptCtrls.isEmpty)
          const Text('留空则按类型给出通用提问',
              style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
        for (var i = 0; i < _promptCtrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptCtrls[i],
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: SuiyaColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => setState(() {
                    _promptCtrls.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () =>
              setState(() => _promptCtrls.add(TextEditingController())),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('加一条提问', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  int _daysInSolarMonth(int month) {
    final y = DateTime.now().year;
    return DateTime(y, month + 1, 0).day;
  }

  Widget _numPicker({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: SuiyaColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SuiyaColors.paperDeep),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: SuiyaColors.inkFaint)),
          const Spacer(),
          Text('$value',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w500, color: SuiyaColors.ink)),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _step(Icons.keyboard_arrow_up, value < max,
                  () => onChanged(value + 1)),
              _step(Icons.keyboard_arrow_down, value > min,
                  () => onChanged(value - 1)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Icon(icon,
              size: 18, color: enabled ? SuiyaColors.inkSoft : SuiyaColors.paperDeep),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
      );
}