/// 岁忆 · 预设项数据访问（data 层）
///
/// 用途：「同行的人」「标签」不再是横线输入框，而是从预设里勾选。
/// 预设分两类（kind）：people（人）/ tag（标签）。
/// 用户在「添加」时可以选择是否存为预设，下次直接勾。
library;

import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';

/// 预设类别
enum PresetKind {
  people,
  tag;

  String get code => name;
  String get label => this == PresetKind.people ? '同行的人' : '标签';

  static PresetKind parse(String? raw) =>
      raw == 'tag' ? PresetKind.tag : PresetKind.people;
}

/// 一个预设项
class Preset {
  final String id;
  final PresetKind kind;
  final String name;
  final int useCount;
  final int createdAt;
  final int updatedAt;

  const Preset({
    required this.id,
    required this.kind,
    required this.name,
    this.useCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });
}

class PresetStore {
  final Database _db;
  PresetStore(this._db);

  Future<List<Preset>> byKind(PresetKind k) async {
    final rows = await _db.query(
      DbSchema.tPresets,
      where: 'kind = ?',
      whereArgs: [k.code],
      orderBy: 'use_count DESC, created_at ASC',
    );
    return rows
        .map((r) => Preset(
              id: (r['id'] as String?) ?? '',
              kind: PresetKind.parse(r['kind'] as String?),
              name: (r['name'] as String?) ?? '',
              useCount: (r['use_count'] as int?) ?? 0,
              createdAt: (r['created_at'] as int?) ?? 0,
              updatedAt: (r['updated_at'] as int?) ?? 0,
            ))
        .toList();
  }

  /// 按名称查（用于判断是否已存在）
  Future<Preset?> findByName(PresetKind k, String name) async {
    final rows = await _db.query(
      DbSchema.tPresets,
      where: 'kind = ? AND name = ?',
      whereArgs: [k.code, name],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Preset(
      id: (r['id'] as String?) ?? '',
      kind: PresetKind.parse(r['kind'] as String?),
      name: (r['name'] as String?) ?? '',
      useCount: (r['use_count'] as int?) ?? 0,
      createdAt: (r['created_at'] as int?) ?? 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
    );
  }

  Future<void> save(Preset p) async {
    await _db.insert(DbSchema.tPresets, {
      'id': p.id,
      'kind': p.kind.code,
      'name': p.name,
      'use_count': p.useCount,
      'created_at': p.createdAt,
      'updated_at': p.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 新增或累加使用次数（同名则 +1，不改名）
  Future<void> addOrBump(PresetKind kind, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final exist = await findByName(kind, trimmed);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (exist == null) {
      await save(Preset(
        id: '${kind.code}_${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        name: trimmed,
        useCount: 1,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      await save(Preset(
        id: exist.id,
        kind: kind,
        name: exist.name,
        useCount: exist.useCount + 1,
        createdAt: exist.createdAt,
        updatedAt: now,
      ));
    }
  }

  Future<void> delete(String id) async {
    await _db.delete(DbSchema.tPresets, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByName(PresetKind kind, String name) async {
    await _db.delete(DbSchema.tPresets,
        where: 'kind = ? AND name = ?', whereArgs: [kind.code, name]);
  }
}