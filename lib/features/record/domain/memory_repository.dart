/// 岁忆 · 记录仓储接口（domain 层）
///
/// domain 只定义"能做什么"，不关心用 sqflite 还是内存实现 —— 这样
/// 业务规则可以脱离 UI 和数据库单测，将来换存储也只需换一个实现。
library;

import 'memory_record.dart';

/// 记录读写接口。
abstract class MemoryRepository {
  Future<void> init();

  Future<List<MemoryRecord>> all();

  /// 某一年（按创建年份筛）
  Future<List<MemoryRecord>> byYear(int year);

  /// 取某节日在指定年份的那条记录（没有则 null）
  Future<MemoryRecord?> find(String festivalId, int year);

  Future<MemoryRecord?> byId(String id);

  Future<void> save(MemoryRecord record);

  Future<void> delete(String id);

  /// 某条记录的媒体
  Future<List<MediaRef>> mediaOf(String recordId);

  /// 未来 N 天内、开启了提醒的记录
  Future<List<MemoryRecord>> upcomingReminders({int withinDays = 30});

  Future<void> dispose();
}

/// 媒体引用（阶段 1 只落库，文件写入在阶段 2）
class MediaRef {
  final String id;
  final String recordId;

  /// photo / voice / video
  final String kind;
  final String path;
  final int? bytes;

  const MediaRef({
    required this.id,
    required this.recordId,
    required this.kind,
    required this.path,
    this.bytes,
  });
}

/// 地点（墓园 / 祖厝 / 常去地）
class PlaceRef {
  final String id;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;

  /// grave / ancestral / other
  final String kind;
  final String? note;
  final SyncPolicy syncPolicy;

  const PlaceRef({
    required this.id,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.kind = 'grave',
    this.note,
    this.syncPolicy = SyncPolicy.localOnly,
  });
}
