/// 岁忆 · 地点领域模型（墓园 / 祖厝 / 常去地）
///
/// 设计要点：**墓园位置默认 LOCAL_ONLY，永不上传** —— 这是产品的隐私底线。
library;

import '../../record/domain/memory_record.dart' show SyncPolicy;

/// 地点类型
enum PlaceKind {
  /// 墓园 / 公墓
  grave,

  /// 祖厝 / 老宅
  ancestral,

  /// 常去的地方
  other;

  String get label => switch (this) {
        PlaceKind.grave => '墓园',
        PlaceKind.ancestral => '祖厝',
        PlaceKind.other => '常去',
      };

  static PlaceKind parse(String raw) => PlaceKind.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => PlaceKind.other,
      );
}

/// 一个地点
class Place {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final PlaceKind kind;

  /// 关联的节日（用于"每年这时候该去这里"）
  final List<String> festivalIds;
  final String? note;
  final SyncPolicy syncPolicy;
  final int createdAt;
  final int updatedAt;

  const Place({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.kind = PlaceKind.grave,
    this.festivalIds = const [],
    this.note,
    this.syncPolicy = SyncPolicy.localOnly,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 是否有可导航的坐标
  bool get canNavigate => lat != null && lng != null;

  /// 坐标文本（用于复制分享）
  String? get coordText =>
      canNavigate ? '${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}' : null;

  /// copyWith 里可空字段的「未传」哨兵：
  /// 直接用 `??` 的话，编辑页点「清除坐标」后传 null 会被当成
  /// 「保留旧值」，UI 显示已清除但保存的地点仍可导航。
  static const Object _unset = Object();

  Place copyWith({
    String? name,
    Object? address = _unset,
    Object? lat = _unset,
    Object? lng = _unset,
    PlaceKind? kind,
    List<String>? festivalIds,
    Object? note = _unset,
    SyncPolicy? syncPolicy,
    int? updatedAt,
  }) {
    return Place(
      id: id,
      name: name ?? this.name,
      address:
          identical(address, _unset) ? this.address : address as String?,
      lat: identical(lat, _unset) ? this.lat : lat as double?,
      lng: identical(lng, _unset) ? this.lng : lng as double?,
      kind: kind ?? this.kind,
      festivalIds: festivalIds ?? this.festivalIds,
      note: identical(note, _unset) ? this.note : note as String?,
      syncPolicy: syncPolicy ?? this.syncPolicy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Place($name, ${kind.label}, 可导航=$canNavigate)';
}
