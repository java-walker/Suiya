/// 岁忆 · sqflite 仓储实现（data 层）
///
/// 依赖方向：data → domain。这里把 domain 的实体映射到数据库行。
library;

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';
import '../domain/memory_codec.dart';
import '../domain/memory_record.dart';
import '../domain/memory_repository.dart';

/// sqflite 实现
class SqfliteMemoryRepository implements MemoryRepository {
  final Database db;

  SqfliteMemoryRepository(this.db);

  static Future<SqfliteMemoryRepository> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'suiya.db'),
      version: DbSchema.version,
      onCreate: (db, version) async {
        for (final stmt in DbSchema.createStatements) {
          await db.execute(stmt);
        }
      },
      // 老库（v1）必须走增量迁移 —— 尤其 places 缺 festival_tags 列，
      // 不迁移的话老用户保存地点依旧会抛异常。
      onUpgrade: (db, from, to) async {
        await DbSchema.migrate(db, from, to);
      },
    );
    return SqfliteMemoryRepository(db);
  }

  @override
  Future<void> init() async {}

  MemoryRecord _fromRow(Map<String, Object?> r) => MemoryRecord(
        id: r[DbSchema.cId] as String,
        festivalId: r[DbSchema.cFestivalId] as String?,
        year: r[DbSchema.cYear] as int,
        title: r[DbSchema.cTitle] as String,
        text: (r[DbSchema.cText] as String?) ?? '',
        qa: MemoryCodec.parseQa(r[DbSchema.cQa] as String?),
        recurrence: RecurrenceX.parse(
            (r[DbSchema.cRecurrence] as String?) ?? 'once'),
        advanceDays: (r[DbSchema.cAdvanceDays] as int?) ?? 1,
        remindOn: ((r[DbSchema.cRemindOn] as int?) ?? 0) == 1,
        participants: MemoryCodec.splitList(r[DbSchema.cParticipants] as String?),
        tags: MemoryCodec.splitList(r[DbSchema.cTags] as String?),
        lat: (r[DbSchema.cLat] as num?)?.toDouble(),
        lng: (r[DbSchema.cLng] as num?)?.toDouble(),
        placeId: r[DbSchema.cPlaceId] as String?,
        address: r[DbSchema.cAddress] as String?,
        syncPolicy: SyncPolicy.parse(
            (r[DbSchema.cSyncPolicy] as String?) ?? 'LOCAL_ONLY'),
        createdAt: r[DbSchema.cCreatedAt] as int,
        updatedAt: r[DbSchema.cUpdatedAt] as int,
      );

  Map<String, Object?> _toRow(MemoryRecord r) => {
        DbSchema.cId: r.id,
        DbSchema.cFestivalId: r.festivalId,
        DbSchema.cYear: r.year,
        DbSchema.cTitle: r.title,
        DbSchema.cText: r.text,
        DbSchema.cQa: MemoryCodec.dumpQa(r.qa),
        DbSchema.cRecurrence: r.recurrence.name,
        DbSchema.cAdvanceDays: r.advanceDays,
        DbSchema.cRemindOn: r.remindOn ? 1 : 0,
        DbSchema.cParticipants: jsonEncode(r.participants),
        DbSchema.cTags: jsonEncode(r.tags),
        DbSchema.cLat: r.lat,
        DbSchema.cLng: r.lng,
        DbSchema.cPlaceId: r.placeId,
        DbSchema.cAddress: r.address,
        DbSchema.cSyncPolicy: r.syncPolicy.dbValue,
        DbSchema.cCreatedAt: r.createdAt,
        DbSchema.cUpdatedAt: r.updatedAt,
      };

  @override
  Future<List<MemoryRecord>> all() async {
    final rows = await db.query(DbSchema.tRecords, orderBy: 'year DESC, created_at DESC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<MemoryRecord>> byYear(int year) async {
    final rows = await db.query(
      DbSchema.tRecords,
      where: '${DbSchema.cYear} = ?',
      whereArgs: [year],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<MemoryRecord?> find(String festivalId, int year) async {
    final rows = await db.query(
      DbSchema.tRecords,
      where: '${DbSchema.cFestivalId} = ? AND ${DbSchema.cYear} = ?',
      whereArgs: [festivalId, year],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<MemoryRecord?> byId(String id) async {
    final rows = await db.query(
      DbSchema.tRecords,
      where: '${DbSchema.cId} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> save(MemoryRecord record) async {
    await db.insert(
      DbSchema.tRecords,
      _toRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String id) async {
    await db.delete(DbSchema.tRecords,
        where: '${DbSchema.cId} = ?', whereArgs: [id]);
    await db.delete(DbSchema.tMedia,
        where: 'record_id = ?', whereArgs: [id]);
  }

  @override
  Future<List<MediaRef>> mediaOf(String recordId) async {
    final rows = await db.query(DbSchema.tMedia,
        where: 'record_id = ?', whereArgs: [recordId]);
    return rows
        .map((r) => MediaRef(
              id: r['id'] as String,
              recordId: r['record_id'] as String,
              kind: r['kind'] as String,
              path: r['path'] as String,
              bytes: r['bytes'] as int?,
            ))
        .toList();
  }

  @override
  Future<List<MemoryRecord>> upcomingReminders({int withinDays = 30}) async {
    final rows = await db.query(
      DbSchema.tRecords,
      where: '${DbSchema.cRemindOn} = 1',
    );
    final res = rows
        .map(_fromRow)
        .where((r) {
          final d = r.daysUntil;
          return d != null && d >= 0 && d <= withinDays;
        })
        .toList()
      ..sort((a, b) =>
          (a.daysUntil ?? 1 << 30).compareTo(b.daysUntil ?? 1 << 30));
    return res;
  }

  @override
  Future<void> dispose() async {
    await db.close();
  }
}
