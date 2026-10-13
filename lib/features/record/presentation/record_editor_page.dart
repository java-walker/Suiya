/// 岁忆 · 记录编辑页
///
/// 核心设计：**用引导提问降低记录门槛** —— 用户不必自己想写什么，
/// 按节日类型给出贴合场景的问题，逐条作答即可成篇。
///
/// v1.4.0 修复的关键问题：
///   1. 选图用 `_pendingId()`、保存用 `_newId()` → 媒体行的 record_id 与
///      记录 id 对不上，图片「保存了但关联不上」。现在统一用 `_recId()`。
///   2. `Navigator.pop(true)` 之后立刻用该 context 弹 SnackBar → context
///      已失效抛异常。现在 pop 前先抓 ScaffoldMessenger。
///   3. 任何保存异常都会让 `_saving` 永不复位，按钮变灰「点了没反应」。
///      现在全程 try/catch/finally + 错误提示。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/festival/festival.dart';
import '../../../core/theme.dart';
import '../../custom_festival/domain/custom_festival.dart';
import '../../log/service/log_service.dart';
import '../../place/presentation/map_launcher.dart';
import '../../preset/data/preset_store.dart';
import '../../reminder/service/reminder_service.dart';
import '../data/media_store.dart';
import '../domain/memory_record.dart';
import 'preset_picker.dart';
import 'record_providers.dart';

/// 生成一个稳定的记录 id（时间戳 + hash 足够本地唯一）
String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '-${DateTime.now().hashCode.toRadixString(36)}';

class RecordEditorPage extends ConsumerStatefulWidget {
  /// 新建时传节日；编辑已有记录时传 record
  final Festival? festival;
  final MemoryRecord? existing;

  const RecordEditorPage({super.key, this.festival, this.existing});

  @override
  ConsumerState<RecordEditorPage> createState() => _RecordEditorPageState();
}

class _RecordEditorPageState extends ConsumerState<RecordEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  final Map<String, TextEditingController> _qaCtl = {};

  /// 同行的人 / 标签（改为预设勾选，不再是横线输入框）
  List<String> _participants = [];
  List<String> _tags = [];

  late List<PromptTemplate> _prompts;
  bool _saving = false;

  // ---------- 照片 ----------
  /// 已保存的相对路径
  final List<String> _photos = [];

  /// 已在数据库中的媒体行（编辑时恢复，用于计算「哪些是新增的」）
  final List<String> _knownPhotoPaths = [];

  String? _placeId;
  String? _address;
  double? _lat;
  double? _lng;
  bool _remindOn = false;
  int _advanceDays = 1;

  /// 新建时先占一个 id，选图与保存共用它 —— 这是 v1.3.0 图片关联断裂的根因
  String? _pendingIdCache;
  String _recId() =>
      widget.existing?.id ?? (_pendingIdCache ??= _newId());

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final f = widget.festival;
    _title = TextEditingController(
        text: e?.title ?? (f == null ? '' : '${DateTime.now().year}年${f.name}'));
    _text = TextEditingController(text: e?.text ?? '');
    _participants = List.of(e?.participants ?? const []);
    _tags = List.of(e?.tags ?? const []);
    // 新建时用节日默认提前量初始化：否则 slider 显示「提前 3 天」（节日默认），
    // 实际保存的却是 _advanceDays 的初始值 1，显示与存储不一致
    _advanceDays = e?.advanceDays ?? (f?.defaultAdvanceDays ?? 1);

    // 引导提问：节日库自带 prompts（含 placeholder），没有则按分类兜底
    final festival = e?.festivalId != null
        ? _resolveFestival(e!.festivalId!)
        : f;
    _prompts = (festival?.prompts.isNotEmpty ?? false)
        ? festival!.prompts
        : _fallbackFor(festival?.category);

    // 自定义节日：内置查不到，异步补上它自己的 prompts
    final festId = e?.festivalId ?? f?.id;
    if (festId != null && _resolveFestival(festId) == null) {
      Future.microtask(() => _loadCustomPrompts(festId));
    }

    // 已有记录：把已答的问答填回控制器
    final answered = {for (final q in (e?.qa ?? const <QaItem>[])) q.question: q.answer};
    for (final q in _prompts) {
      _qaCtl[q.question] = TextEditingController(text: answered[q.question] ?? '');
    }

    // 恢复编辑态
    if (e != null) {
      _placeId = e.placeId;
      _address = e.address;
      _lat = e.lat;
      _lng = e.lng;
      _remindOn = e.remindOn;
      _advanceDays = e.advanceDays;
      Future.microtask(() async {
        final media = await ref.read(mediaStoreProvider).ofRecord(e.id);
        if (!mounted) return;
        setState(() {
          final paths = media.where((m) => m.kind == 'photo').map((m) => m.path).toList();
          _photos.addAll(paths);
          _knownPhotoPaths.addAll(paths);
        });
      });
    }
  }

  /// 解析节日 id（内置 + 二十四节气）
  ///
  /// 自定义节日走异步补：initState 是同步的，而自定义集合在 provider 里，
  /// 所以先返回内置结果，拿到后再 setState 替换成自定义的 prompts。
  Festival? _resolveFestival(String id) {
    final builtin = Festivals.byId(id);
    if (builtin != null) return builtin;
    for (final t in Festivals.allTerms()) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 编辑已有记录时，自定义节日的 prompts 需要异步取回再套用
  Future<void> _loadCustomPrompts(String id) async {
    if (!id.startsWith('custom_')) return;
    try {
      final customs = await ref.read(customFestivalsProvider.future);
      if (!mounted) return;
      CustomFestival? matched;
      for (final c in customs) {
        if (c.id == id) {
          matched = c;
          break;
        }
      }
      if (matched == null || matched.prompts.isEmpty) return;
      final f = matched.asFestival();
      // 记录里可能已经答过旧问题，不要把已填的答案丢掉
      final answered = {
        for (final q in (widget.existing?.qa ?? const <QaItem>[])) q.question: q.answer
      };
      setState(() {
        _prompts = f.prompts;
        for (final q in f.prompts) {
          _qaCtl[q.question] ??=
              TextEditingController(text: answered[q.question] ?? '');
        }
      });
    } catch (e) {
      LogService.exception('记录', '自定义节日提问加载失败', e, null);
    }
  }

  /// 按分类兜底的提问
  static List<PromptTemplate> _fallbackFor(FestivalCategory? c) {
    switch (c) {
      case FestivalCategory.memorial:
        return const [
          PromptTemplate('今年和谁一起？'),
          PromptTemplate('做了什么？'),
          PromptTemplate('想说的话'),
        ];
      case FestivalCategory.worship:
        return const [
          PromptTemplate('在哪里上香？'),
          PromptTemplate('和谁一起？'),
          PromptTemplate('许了什么愿'),
        ];
      default:
        return const [
          PromptTemplate('今天发生了什么？'),
          PromptTemplate('和谁一起？'),
          PromptTemplate('最想记住的一个细节'),
        ];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    for (final c in _qaCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('给这条记录起个标题吧');
      return;
    }
    if (_saving) return;

    // 关键：pop 之前先拿到 ScaffoldMessenger，pop 之后 context 就失效了
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final qa = <QaItem>[];
      for (final q in _prompts) {
        final a = _qaCtl[q.question]?.text.trim() ?? '';
        if (a.isNotEmpty) qa.add(QaItem(q.question, a));
      }

      final e = widget.existing;
      final f = widget.festival;
      // slider 选什么就存什么（0 = 当天早上提醒），不再把 0 吞成节日默认值
      final days = _advanceDays;

      final record = e == null
          ? MemoryRecord(
              id: _recId(),
              festivalId: f?.id,
              year: DateTime.now().year,
              title: title,
              text: _text.text.trim(),
              qa: qa,
              participants: _participants,
              tags: _tags,
              advanceDays: days,
              remindOn: _remindOn,
              placeId: _placeId,
              address: _address,
              lat: _lat,
              lng: _lng,
              createdAt: now,
              updatedAt: now,
            )
          : e.copyWith(
              title: title,
              text: _text.text.trim(),
              qa: qa,
              participants: _participants,
              tags: _tags,
              advanceDays: days,
              remindOn: _remindOn,
              placeId: _placeId,
              address: _address,
              lat: _lat,
              lng: _lng,
              updatedAt: now,
            );

      // ---- 照片：先把 record 落库，再挂 media 行 ----
      // 顺序很重要：先写 records，媒体行才有可靠的 record_id 外键指向
      await ref.read(recordActionsProvider).save(record);

      final store = ref.read(mediaStoreProvider);
      final known = _knownPhotoPaths.toSet();

      // 新增的图片
      for (final rel in _photos) {
        if (known.contains(rel)) continue;
        await store.add(recordId: record.id, kind: 'photo', relativePath: rel);
        LogService.info('照片', '已关联照片',
            detail: 'record=${record.id} path=$rel');
      }

      // 被移除的照片：删掉数据库行与文件
      final removed = known.difference(_photos.toSet());
      if (removed.isNotEmpty) {
        await store.removePaths(record.id, removed.toList());
        LogService.info('照片', '已移除 ${removed.length} 张照片',
            detail: 'record=${record.id}');
      }

      // 回写已入库照片：否则首次保存部分成功后重试，
      // 已入库的照片会再插一遍（生成重复媒体行）
      if (mounted) {
        setState(() {
          _knownPhotoPaths
            ..clear()
            ..addAll(_photos);
        });
      }

      // ---- 提醒 ----
      if (_remindOn) {
        final at = await ReminderService.scheduleFor(record);
        LogService.info('提醒',
            at == null ? '提醒未安排（可能日期已过或初始化失败）' : '提醒已安排',
            detail: 'record=${record.id} fireAt=$at');
      } else if (e != null) {
        await ReminderService.cancel(record.id);
      }

      if (!mounted) return;
      // 时间轴上可能不是这个日子（例如从「去记录」进的），刷新全部相关 provider
      ref.invalidate(timelineProvider(DateTime.now().year));
      ref.invalidate(mediaOfProvider(record.id));

      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('已记下「$title」')),
      );
    } catch (err, st) {
      LogService.exception('记录', '保存失败「$title」', err, st);
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.festival;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '记一笔' : '编辑记录'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          if (f != null) _festBanner(f),
          _label('标题'),
          TextField(
            controller: _title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(
              hintText: '例如：清明·上山祭祖',
              border: UnderlineInputBorder(
                borderSide: BorderSide(color: SuiyaColors.paperDeep),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _label('引导提问'),
          ..._prompts.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.question,
                        style: const TextStyle(
                            fontSize: 13,
                            color: SuiyaColors.cinnabar,
                            fontWeight: FontWeight.w500)),
                    if (q.placeholder != null) ...[
                      const SizedBox(height: 2),
                      Text(q.placeholder!,
                          style: const TextStyle(
                              fontSize: 11, color: SuiyaColors.inkFaint)),
                    ],
                    const SizedBox(height: 6),
                    TextField(
                      controller: _qaCtl[q.question],
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: '（可留空）',
                        isDense: true,
                        filled: true,
                        fillColor: SuiyaColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          _label('还想写点什么'),
          TextField(
            controller: _text,
            maxLines: 8,
            minLines: 4,
            decoration: InputDecoration(
              hintText: '自由记录…',
              filled: true,
              fillColor: SuiyaColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 问题 4：同行的人 —— 旋转展开的预设勾选面板
          _label('同行的人'),
          PresetPicker(
            kind: PresetKind.people,
            icon: Icons.people_outline,
            selected: _participants,
            onChanged: (v) => setState(() => _participants = v),
          ),
          const SizedBox(height: 20),

          // 问题 4：标签 —— 同样改成预设勾选
          _label('标签'),
          PresetPicker(
            kind: PresetKind.tag,
            icon: Icons.local_offer_outlined,
            selected: _tags,
            onChanged: (v) => setState(() => _tags = v),
          ),
          const SizedBox(height: 24),

          _label('照片'),
          _photoGrid(),
          const SizedBox(height: 24),
          _label('地点'),
          _placePicker(),
          const SizedBox(height: 24),
          _label('提醒'),
          _reminderSwitch(),
        ],
      ),
    );
  }

  // ---------- 照片九宫格 ----------

  Widget _photoGrid() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 添加按钮
          GestureDetector(
            onTap: _pickPhotos,
            child: Container(
              width: 88,
              height: 88,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: SuiyaColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SuiyaColors.paperDeep),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 22, color: SuiyaColors.inkFaint),
                  SizedBox(height: 4),
                  Text('添加', style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
                ],
              ),
            ),
          ),
          for (final rel in _photos)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  FutureBuilder(
                    future: MediaStore.absolutePath(rel),
                    builder: (context, snap) {
                      final p = snap.data;
                      if (p == null) {
                        return Container(
                          width: 88,
                          height: 88,
                          color: SuiyaColors.surface,
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(p),
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 88,
                            height: 88,
                            color: SuiyaColors.surface,
                            child: const Icon(Icons.broken_image,
                                size: 18, color: SuiyaColors.inkFaint),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _photos.remove(rel)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xCC000000),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(
        imageQuality: 85,          // 压缩交给 image_picker，避免额外原生依赖
        maxWidth: 1600,
      );
      if (picked.isEmpty) return;
      // 关键：用 _recId()，与保存时完全一致的 id
      final recId = _recId();
      final rels = <String>[];
      for (final f in picked) {
        rels.add(await MediaStore.importImage(f.path, recId));
      }
      if (!mounted) return;
      setState(() => _photos.addAll(rels));
      LogService.info('照片', '已选择 ${rels.length} 张照片',
          detail: 'recordId=$recId');
      _toast('已选 ${rels.length} 张，别忘了点右上角保存');
    } catch (e, st) {
      LogService.exception('照片', '选择照片失败', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择照片失败：$e')));
      }
    }
  }

  // ---------- 地点选择 ----------

  Widget _placePicker() {
    final async = ref.watch(placesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        async.when(
          loading: () => const Text('读取地点…',
              style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
          error: (e, _) => Text('读取失败：$e',
              style: const TextStyle(fontSize: 12, color: SuiyaColors.cinnabar)),
          data: (places) {
            if (places.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('还没有保存的地点',
                      style:
                          TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    // v1.3.0 用了 Navigator.pushNamed —— 在 go_router 下
                    // 会静默失败，表现为「点了没反应」。现在统一 context.push。
                    onPressed: () => context.push('/places'),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('去添加墓园或老家',
                        style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SuiyaColors.cinnabar,
                      side: BorderSide(
                          color: SuiyaColors.cinnabar.withOpacity(0.35)),
                    ),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final pl in places)
                      ChoiceChip(
                        label: Text(pl.name, style: const TextStyle(fontSize: 12)),
                        selected: _placeId == pl.id,
                        selectedColor: SuiyaColors.cinnabar.withOpacity(0.15),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _placeId = pl.id;
                            _address = pl.address;
                            _lat = pl.lat;
                            _lng = pl.lng;
                          } else {
                            _placeId = null;
                            _address = null;
                            _lat = null;
                            _lng = null;
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push('/places'),
                    icon: const Icon(Icons.place_outlined, size: 15),
                    label: const Text('管理地点', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        foregroundColor: SuiyaColors.inkSoft),
                  ),
                ),
              ],
            );
          },
        ),
        if (_address != null || _lat != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SuiyaColors.paperDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.place_outlined,
                    size: 14, color: SuiyaColors.inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _address ?? (_lat != null ? '已选坐标' : ''),
                    style: const TextStyle(
                        fontSize: 12, color: SuiyaColors.inkSoft),
                  ),
                ),
                if (_lat != null)
                  // 有坐标就能一键导航，顺手解决「点地点没反应」
                  TextButton.icon(
                    onPressed: _navigateSelected,
                    icon: const Icon(Icons.navigation, size: 14),
                    label: const Text('导航', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: SuiyaColors.cinnabar,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _navigateSelected() async {
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) {
      _toast('这个地点还没有坐标');
      return;
    }
    final name = _address ?? '这个地方';
    final ok = await MapLauncher.navigate(lat: lat, lng: lng, name: name);
    if (ok) {
      LogService.info('地点', '已唤起导航', detail: '$lat, $lng');
    } else {
      LogService.warning('地点', '导航唤起失败', detail: '$lat, $lng');
    }
    if (!ok && mounted) {
      await MapLauncher.copyCoordinates(lat, lng);
      if (!mounted) return;
      _toast('没有可用地图应用，坐标已复制');
    }
  }

  // ---------- 提醒 ----------

  Widget _reminderSwitch() {
    final f = widget.festival;
    final defaultDays = f?.defaultAdvanceDays ?? 1;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('提前 $effectiveDays 天提醒我',
                  style: const TextStyle(fontSize: 14, color: SuiyaColors.ink)),
            ),
            Switch(
              value: _remindOn,
              activeColor: SuiyaColors.cinnabar,
              onChanged: (v) => setState(() => _remindOn = v),
            ),
          ],
        ),
        if (_remindOn) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text('提前',
                  style:
                      const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
              Expanded(
                child: Slider(
                  value: effectiveDays.toDouble().clamp(0, 14),
                  min: 0,
                  max: 14,
                  divisions: 14,
                  activeColor: SuiyaColors.cinnabar,
                  label: '$effectiveDays 天',
                  onChanged: (v) =>
                      setState(() => _advanceDays = v.round()),
                ),
              ),
              Text('$effectiveDays 天',
                  style: const TextStyle(fontSize: 12, color: SuiyaColors.ink)),
            ],
          ),
          Text('默认 $defaultDays 天（${f?.name ?? '这个日子'}）',
              style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
          const SizedBox(height: 4),
          const Text('保存后可在「设置 → 运行日志」查看提醒是否安排成功',
              style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
        ],
      ],
    );
  }

  int get effectiveDays => _advanceDays;

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            color: SuiyaColors.inkFaint,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _festBanner(Festival f) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [SuiyaColors.cinnabar.withOpacity(0.10), SuiyaColors.paperDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(f.name,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: SuiyaColors.ink,
                    letterSpacing: 2)),
            const Spacer(),
            if (f.note != null)
              Flexible(
                child: Text(f.note!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
              ),
          ],
        ),
      );
}