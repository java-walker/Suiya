/// 岁忆 · 墓园 / 常去地点管理
///
/// 差异化功能：墓园定位与一键导航（竞品空白）。
/// 隐私：墓园位置强制 LOCAL_ONLY，永不上传。
///
/// v1.4.0 修复：
///   1. `Navigator.pushNamed` 在 go_router 下静默失败 → 全部改用 context.push
///   2. 导航只试高德一个 URL，失败就「没反应」→ 改用多级兜底 MapLauncher
///   3. 没有坐标时无法导航 → 增加手动填坐标
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme.dart';
import '../../log/service/log_service.dart';
import '../../record/data/media_store.dart';
import '../../record/presentation/record_providers.dart';
import '../domain/place.dart';
import 'map_launcher.dart';

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-p';

class PlaceListPage extends ConsumerWidget {
  const PlaceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(placesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('墓园与常去的地方')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: SuiyaColors.cinnabar,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('新增', style: TextStyle(color: Colors.white)),
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
        data: (places) {
          if (places.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.place_outlined,
                        size: 48, color: SuiyaColors.inkFaint),
                    SizedBox(height: 16),
                    Text('还没有记录地点',
                        style: TextStyle(fontSize: 16, color: SuiyaColors.ink)),
                    SizedBox(height: 8),
                    Text(
                      '把墓园、老家、常去的地方记下来\n记的时候可以一键带出，还能直接导航',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: SuiyaColors.inkFaint),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final p in places)
                _PlaceTile(
                  place: p,
                  onTap: () => _edit(context, ref, p),
                  onNavigate: () => _navigate(context, p),
                  onShowMap: p.canNavigate ? () => _showMap(context, p) : null,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PlaceTile extends ConsumerWidget {
  final Place place;
  final VoidCallback onTap;
  final VoidCallback onNavigate;
  final VoidCallback? onShowMap;

  const _PlaceTile({
    required this.place,
    required this.onTap,
    required this.onNavigate,
    this.onShowMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(placePhotosProvider(place.id));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: SuiyaColors.paperDeep,
                borderRadius: BorderRadius.circular(10),
              ),
              child: photos.when(
                loading: () => _kindIcon(),
                error: (_, __) => _kindIcon(),
                data: (list) {
                  if (list.isEmpty) return _kindIcon();
                  // 有照片：展示第一张缩略图，而不是类型图标
                  return FutureBuilder(
                    future: MediaStore.absolutePath(list.first.path),
                    builder: (ctx, snap) {
                      final p = snap.data;
                      if (p == null) return _kindIcon();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(p),
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _kindIcon(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(place.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, color: SuiyaColors.ink)),
                      ),
                      const SizedBox(width: 8),
                      _tag(place.kind.label),
                      if (place.syncPolicy.name == 'localOnly') ...[
                        const SizedBox(width: 6),
                        _tag('仅本地'),
                      ],
                    ],
                  ),
                  if (place.address != null && place.address!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(place.address!,
                          style: const TextStyle(
                              fontSize: 12, color: SuiyaColors.inkFaint)),
                    ),
                  if (!place.canNavigate)
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Text('还没有坐标，点这里补上',
                          style: TextStyle(fontSize: 11, color: SuiyaColors.ochre)),
                    ),
                ],
              ),
            ),
            // 「在地图上看看」——没有它用户点哪都没反应
            if (onShowMap != null)
              IconButton(
                icon: const Icon(Icons.map_outlined, size: 19),
                color: SuiyaColors.inkSoft,
                onPressed: onShowMap,
                tooltip: '在地图上查看',
              ),
            // 「导航」始终显示：没坐标时给出明确反馈而不是空白
            IconButton(
              icon: Icon(
                place.canNavigate
                    ? Icons.navigation
                    : Icons.location_searching,
                size: 20,
              ),
              color: place.canNavigate ? SuiyaColors.cinnabar : SuiyaColors.inkFaint,
              onPressed: onNavigate,
              tooltip: place.canNavigate ? '一键导航' : '需要坐标',
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindIcon() => Icon(
        switch (place.kind) {
          PlaceKind.grave => Icons.landscape_outlined,
          PlaceKind.ancestral => Icons.home_outlined,
          PlaceKind.other => Icons.place_outlined,
        },
        size: 19,
        color: SuiyaColors.inkSoft,
      );

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: SuiyaColors.paperDeep,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(t,
            style: const TextStyle(fontSize: 10, color: SuiyaColors.inkFaint)),
      );
}

/// 一键导航
Future<void> _navigate(BuildContext context, Place p) async {
  if (!p.canNavigate) {
    LogService.warning('地点', '「${p.name}」没有坐标，无法导航');
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: const Text('还没有坐标', style: TextStyle(fontSize: 16)),
        content: Text(
          '「${p.name}」没有坐标，无法导航。\n\n'
          '可以打开编辑页用「用当前位置」定位，\n或手动填写经纬度。',
          style: const TextStyle(fontSize: 13, color: SuiyaColors.inkSoft, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('知道了')),
        ],
      ),
    );
    return;
  }

  final ok = await MapLauncher.navigate(lat: p.lat!, lng: p.lng!, name: p.name);
  if (ok) {
    LogService.info('地点', '已唤起导航「${p.name}」',
        detail: '${p.lat}, ${p.lng}');
  } else {
    LogService.warning('地点', '导航唤起失败「${p.name}」', detail: '未安装任何地图应用');
    if (!context.mounted) return;
    // 兜底：复制坐标，让用户能手动粘贴到任意地图 App
    await MapLauncher.copyCoordinates(p.lat!, p.lng!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('没找到可用的地图应用，坐标已复制：${p.lat!.toStringAsFixed(5)}, ${p.lng!.toStringAsFixed(5)}'),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

/// 在地图上查看（不导航）
Future<void> _showMap(BuildContext context, Place p) async {
  final ok = await MapLauncher.showOnMap(lat: p.lat!, lng: p.lng!, name: p.name);
  if (!ok) {
    LogService.warning('地点', '地图唤起失败「${p.name}」');
    if (!context.mounted) return;
    await MapLauncher.copyCoordinates(p.lat!, p.lng!);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('没找到地图应用，坐标已复制到剪贴板')),
    );
  }
}

/// 新增 / 编辑地点
Future<void> _edit(BuildContext context, WidgetRef ref, Place? existing) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlaceEditPage(existing: existing)),
  );
  ref.invalidate(placesProvider);
}

class PlaceEditPage extends ConsumerStatefulWidget {
  final Place? existing;
  const PlaceEditPage({super.key, this.existing});

  @override
  ConsumerState<PlaceEditPage> createState() => _PlaceEditPageState();
}

class _PlaceEditPageState extends ConsumerState<PlaceEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _note;
  late PlaceKind _kind;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _saving = false;

  /// 地点 id：新建时先占一个，选图与保存共用 —— 避免图片关联不上（记录编辑页同款坑）
  late final String _pid;

  // ---------- 照片 ----------
  final List<String> _photos = [];
  final List<String> _knownPhotoPaths = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _kind = e?.kind ?? PlaceKind.grave;
    _lat = e?.lat;
    _lng = e?.lng;
    _pid = e?.id ?? _newId();

    if (e != null) {
      Future.microtask(() async {
        final media = await ref.read(mediaStoreProvider).ofRecord(e.id);
        if (!mounted) return;
        setState(() {
          final paths =
              media.where((m) => m.kind == 'photo').map((m) => m.path).toList();
          _photos.addAll(paths);
          _knownPhotoPaths.addAll(paths);
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        LogService.warning('地点', '定位权限被拒绝');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要定位权限才能记录坐标，可在系统设置里开启')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
        LogService.info('地点', '定位成功',
            detail: '${pos.latitude}, ${pos.longitude}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已定位到 ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}')),
        );
      }
    } catch (e) {
      LogService.exception('地点', '定位失败', e, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位失败：$e\n可在下方手动填写经纬度')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 手动填写坐标（定位失败 / 没权限时的兜底）
  Future<void> _inputCoordinates() async {
    final latCtl = TextEditingController(text: _lat?.toString() ?? '');
    final lngCtl = TextEditingController(text: _lng?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: const Text('手动填写坐标', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('在地图 App 里长按目标位置即可复制经纬度',
                style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
            const SizedBox(height: 12),
            TextField(
              controller: latCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: '纬度 lat', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lngCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: '经度 lng', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      final la = double.tryParse(latCtl.text.trim());
      final ln = double.tryParse(lngCtl.text.trim());
      if (la != null && ln != null && la.abs() <= 90 && ln.abs() <= 180) {
        setState(() {
          _lat = la;
          _lng = ln;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('坐标格式不对，请检查')));
      }
    }
    latCtl.dispose();
    lngCtl.dispose();
  }

  // ---------- 照片九宫格（与记录编辑页同一套交互）----------

  Widget _photoGrid() {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
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
                  Text('添加',
                      style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
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
                            width: 88, height: 88, color: SuiyaColors.surface);
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
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked.isEmpty) return;
      final rels = <String>[];
      for (final f in picked) {
        rels.add(await MediaStore.importImage(f.path, _pid));
      }
      if (!mounted) return;
      setState(() => _photos.addAll(rels));
      LogService.info('地点', '已选择 ${rels.length} 张照片', detail: 'placeId=$_pid');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选 ${rels.length} 张，别忘了点右上角保存')),
      );
    } catch (e, st) {
      LogService.exception('地点', '选择照片失败', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择照片失败：$e')));
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('给这个地方起个名字')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = widget.existing;
    final place = e == null
        ? Place(
            id: _pid,
            name: name,
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            lat: _lat,
            lng: _lng,
            kind: _kind,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            createdAt: now,
            updatedAt: now,
          )
        : e.copyWith(
            name: name,
            address: _address.text.trim(),
            lat: _lat,
            lng: _lng,
            kind: _kind,
            note: _note.text.trim(),
            updatedAt: now,
          );

    try {
      await ref.read(placeActionsProvider).save(place);

      // ---- 照片：先落地点库，再挂媒体行（与记录编辑页一致）----
      final store = ref.read(mediaStoreProvider);
      final known = _knownPhotoPaths.toSet();
      for (final rel in _photos) {
        if (known.contains(rel)) continue;
        await store.add(recordId: place.id, kind: 'photo', relativePath: rel);
      }
      final removed = known.difference(_photos.toSet());
      if (removed.isNotEmpty) {
        await store.removePaths(place.id, removed.toList());
      }
      if (mounted) {
        setState(() {
          _knownPhotoPaths
            ..clear()
            ..addAll(_photos);
        });
      }

      if (!mounted) return;
      // pop 之前先拿 ScaffoldMessenger，pop 之后 context 已失效
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('已保存「$name」')));
    } catch (e) {
      LogService.exception('地点', '保存失败「$name」', e, null);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新增地点' : '编辑地点'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          _label('类型'),
          Wrap(
            spacing: 8,
            children: [
              for (final k in PlaceKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: _kind == k,
                  selectedColor: SuiyaColors.cinnabar.withOpacity(0.15),
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          if (_kind == PlaceKind.grave) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 13, color: SuiyaColors.inkFaint),
                const SizedBox(width: 4),
                const Text('墓园位置只存在本机，不会同步到云端',
                    style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _label('名称'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: '如：南山公墓 / 老家'),
          ),
          const SizedBox(height: 20),
          _label('地址'),
          TextField(
            controller: _address,
            decoration: const InputDecoration(hintText: '选填，便于辨认'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _label('坐标'),
              const Spacer(),
              TextButton.icon(
                onPressed: _locating ? null : _locate,
                icon: _locating
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(_locating ? '定位中' : '用当前位置'),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SuiyaColors.paperDeep,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _lat != null ? Icons.check_circle : Icons.location_off_outlined,
                      size: 16,
                      color: _lat != null ? SuiyaColors.moss : SuiyaColors.inkFaint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _lat == null
                            ? '还没有坐标'
                            : '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _lat != null ? SuiyaColors.ink : SuiyaColors.inkFaint,
                        ),
                      ),
                    ),
                    if (_lat != null)
                      IconButton(
                        icon: const Icon(Icons.close, size: 15),
                        onPressed: () => setState(() {
                          _lat = null;
                          _lng = null;
                        }),
                        tooltip: '清除',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _inputCoordinates,
                      icon: const Icon(Icons.keyboard_alt_outlined, size: 15),
                      label: const Text('手动填写坐标', style: TextStyle(fontSize: 12)),
                    ),
                    const Spacer(),
                    if (_lat != null)
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await MapLauncher.navigate(
                              lat: _lat!, lng: _lng!, name: _name.text.trim().isEmpty ? '这里' : _name.text.trim());
                          if (!ok && mounted) {
                            await MapLauncher.copyCoordinates(_lat!, _lng!);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('没有可用地图应用，坐标已复制')),
                            );
                          }
                        },
                        icon: const Icon(Icons.navigation, size: 15),
                        label: const Text('试一下导航', style: TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _label('备注'),
          TextField(
            controller: _note,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(hintText: '如：走北门比较近'),
          ),
          const SizedBox(height: 24),
          _label('照片'),
          _photoGrid(),
          if (widget.existing != null) ...[
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () async {
                await ref
                    .read(placeActionsProvider)
                    .delete(widget.existing!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(foregroundColor: SuiyaColors.cinnabar),
              child: const Text('删除这个地点'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 表单标签
Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
    );