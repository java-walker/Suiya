/// 岁忆 · 媒体与地点的数据访问（data 层）
///
/// 媒体文件存 App 私有目录，数据库只存相对路径 —— 这样导出/迁移时
/// 只需搬文件目录，且换设备不会丢。
library;

import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';
import '../../place/domain/place.dart';
import '../../record/domain/memory_codec.dart';
import '../../record/domain/memory_record.dart';

/// 媒体管理
class MediaStore {
  final Database _db;

  MediaStore(this._db);

  /// 媒体根目录（App 私有 Documents/media）
  static Future<Directory> mediaRoot() async {
    final dir = await getApplicationDocumentsDirectory();
    final m = Directory(p.join(dir.path, 'media'));
    if (!m.existsSync()) m.createSync(recursive: true);
    return m;
  }

  /// 把选中的图片复制进 media 目录，返回相对路径
  ///
  /// [imageQuality] 交给 image_picker 压缩，避免引入额外原生依赖。
  static Future<String> importImage(String sourcePath, String recordId) async {
    final root = await mediaRoot();
    // 毫秒时间戳会碰撞：同一记录同一毫秒导入两张图会互相覆盖文件，
    // 而 DB 是两行 —— 删其一后另一张变破图。加一段随机后缀兜底。
    final suffix = Random.secure().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final name =
        '${recordId}_${DateTime.now().millisecondsSinceEpoch}_$suffix.jpg';
    final dest = p.join(root.path, name);
    await File(sourcePath).copy(dest);
    return 'media/$name';
  }

  /// 绝对路径
  static Future<String> absolutePath(String relative) async {
    final root = await mediaRoot();
    return p.join(root.path, p.basename(relative));
  }

  /// 同步版绝对路径 —— 供已知 media 根目录的 UI 直接拼路径（如详情弹窗）
  static String absolutePathSync(String relative) {
    final cached = _mediaRootCache;
    if (cached == null) {
      // 尚未初始化时退化为「相对路径去前缀」，至少不会崩
      return p.basename(relative);
    }
    return p.join(cached, p.basename(relative));
  }

  static String? _mediaRootCache;

  /// 同步取媒体根目录（App 启动后调一次即可）
  static Future<String> ensureMediaRoot() async {
    final root = (await mediaRoot()).path;
    _mediaRootCache = root;
    return root;
  }

  /// 写入记录
  Future<void> add({
    required String recordId,
    required String kind,
    required String relativePath,
    int? bytes,
  }) async {
    await _db.insert(DbSchema.tMedia, {
      'id': '${recordId}_${DateTime.now().microsecondsSinceEpoch}',
      'record_id': recordId,
      'kind': kind,
      'path': relativePath,
      'bytes': bytes ??
          (await File(await absolutePath(relativePath)).exists()
              ? (await File(await absolutePath(relativePath))).length()
              : null),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<({String id, String kind, String path, int? bytes})>> ofRecord(
      String recordId) async {
    final rows = await _db.query(DbSchema.tMedia,
        where: 'record_id = ?', whereArgs: [recordId]);
    return rows
        .map((r) => (
              id: r['id'] as String,
              kind: r['kind'] as String,
              path: r['path'] as String,
              bytes: r['bytes'] as int?,
            ))
        .toList();
  }

  Future<int> countAll() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM ${DbSchema.tMedia}');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 某年记录的照片数（按 created_at 年份近似）
  Future<int> countPhotosOfYear(int year) async {
    final from = DateTime(year).millisecondsSinceEpoch;
    final to = DateTime(year + 1).millisecondsSinceEpoch;
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.tMedia} WHERE kind = ? AND created_at >= ? AND created_at < ?',
      ['photo', from, to],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> removeOfRecord(String recordId) async {
    final rows = await _db.query(DbSchema.tMedia,
        where: 'record_id = ?', whereArgs: [recordId]);
    for (final r in rows) {
      final f = File(await absolutePath(r['path'] as String));
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    await _db.delete(DbSchema.tMedia,
        where: 'record_id = ?', whereArgs: [recordId]);
  }

  /// 移除指定的几张照片（编辑时用户删掉了某几张）。
  ///
  /// 只删属于该记录、且路径匹配的行 —— 避免误删其它记录的图片。
  Future<void> removePaths(String recordId, List<String> paths) async {
    if (paths.isEmpty) return;
    for (final rel in paths) {
      final rows = await _db.query(
        DbSchema.tMedia,
        where: 'record_id = ? AND path = ?',
        whereArgs: [recordId, rel],
      );
      if (rows.isEmpty) continue;
      final f = File(await absolutePath(rel));
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      await _db.delete(DbSchema.tMedia,
          where: 'record_id = ? AND path = ?', whereArgs: [recordId, rel]);
    }
  }
}

/// 地点仓储
class PlaceStore {
  final Database _db;

  PlaceStore(this._db);

  static Place _fromRow(Map<String, Object?> r) => Place(
        id: r['id'] as String,
        name: r['name'] as String,
        address: r['address'] as String?,
        lat: (r['lat'] as num?)?.toDouble(),
        lng: (r['lng'] as num?)?.toDouble(),
        kind: PlaceKind.parse((r['kind'] as String?) ?? 'other'),
        festivalIds: MemoryCodec.splitList(r['festival_tags'] as String?),
        note: r['note'] as String?,
        syncPolicy: SyncPolicy.parse(
            (r['sync_policy'] as String?) ?? 'LOCAL_ONLY'),
        createdAt: r['created_at'] as int,
        updatedAt: r['updated_at'] as int,
      );

  Future<List<Place>> all() async {
    final rows = await _db.query(DbSchema.tPlaces, orderBy: 'name COLLATE NOCASE');
    return rows.map(_fromRow).toList();
  }

  Future<List<Place>> byKind(PlaceKind k) async {
    final rows = await _db.query(DbSchema.tPlaces,
        where: 'kind = ?', whereArgs: [k.name], orderBy: 'name COLLATE NOCASE');
    return rows.map(_fromRow).toList();
  }

  Future<Place?> byId(String id) async {
    final rows = await _db.query(DbSchema.tPlaces,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> save(Place place) async {
    await _db.insert(DbSchema.tPlaces, {
      'id': place.id,
      'name': place.name,
      'address': place.address,
      'lat': place.lat,
      'lng': place.lng,
      'kind': place.kind.name,
      'festival_tags': MemoryCodec.dumpList(place.festivalIds),
      'note': place.note,
      // 墓园位置强制仅本地
      'sync_policy': place.kind == PlaceKind.grave
          ? SyncPolicy.localOnly.dbValue
          : place.syncPolicy.dbValue,
      'created_at': place.createdAt,
      'updated_at': place.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete(DbSchema.tPlaces, where: 'id = ?', whereArgs: [id]);
  }
}
