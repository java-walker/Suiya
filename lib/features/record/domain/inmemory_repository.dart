/// 岁忆 · 内存仓储实现（domain 层，纯 Dart）
///
/// 两个用途：
/// 1. 单元测试 —— 不需要 Flutter 引擎，`dart run` 就能跑
/// 2. 数据库不可用时的降级兜底
///
/// 注意：真实 App 里绝不能拿它当主存储（进程一退就丢），
/// 主存储必须是 data 层的 SqfliteMemoryRepository。
library;

import 'memory_record.dart';
import 'memory_repository.dart';

/// 内存实现：单元测试与"数据库不可用"时的降级兜底。
///
/// 真实 App 里绝不能拿它当主存储（进程一退就丢），但它让业务逻辑
/// 可以在没有 Flutter 引擎的环境里被测试。
class InMemoryMemoryRepository implements MemoryRepository {
  final Map<String, MemoryRecord> _store = {};
  final Map<String, List<MediaRef>> _media = {};

  @override
  Future<void> init() async {}

  @override
  Future<List<MemoryRecord>> all() async => _store.values.toList();

  @override
  Future<List<MemoryRecord>> byYear(int year) async =>
      _store.values.where((r) => r.year == year).toList();

  @override
  Future<MemoryRecord?> find(String festivalId, int year) async {
    for (final r in _store.values) {
      if (r.festivalId == festivalId && r.year == year) return r;
    }
    return null;
  }

  @override
  Future<MemoryRecord?> byId(String id) async => _store[id];

  @override
  Future<void> save(MemoryRecord record) async {
    _store[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
    _media.remove(id);
  }

  @override
  Future<List<MediaRef>> mediaOf(String recordId) async =>
      _media[recordId] ?? const [];

  @override
  Future<List<MemoryRecord>> upcomingReminders({int withinDays = 30}) async {
    final res = <MemoryRecord>[];
    for (final r in _store.values) {
      if (!r.remindOn) continue;
      final d = r.daysUntil;
      if (d != null && d >= 0 && d <= withinDays) res.add(r);
    }
    res.sort((a, b) => (a.daysUntil ?? 1 << 30).compareTo(b.daysUntil ?? 1 << 30));
    return res;
  }

  @override
  Future<void> dispose() async {}

  // ---- 同步镜像：供 `dart run` / 同步 test() 使用（不走 event loop）----

  void syncSave(MemoryRecord r) => _store[r.id] = r;

  MemoryRecord? syncFind(String festivalId, int year) {
    for (final r in _store.values) {
      if (r.festivalId == festivalId && r.year == year) return r;
    }
    return null;
  }

  MemoryRecord? syncById(String id) => _store[id];

  void syncDelete(String id) {
    _store.remove(id);
    _media.remove(id);
  }

  int get length => _store.length;
}
