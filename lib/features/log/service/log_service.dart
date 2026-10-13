/// 岁忆 · 日志服务
///
/// 设计要点：
/// 1. 双写 —— 落 SQLite（可在 App 内查看/导出）+ debugPrint（真机 logcat 可见）。
///    v1.3.0 的多个 bug 在真机上无法定位，就是因为没有运行时日志。
/// 2. 永不影响主流程：所有写日志的异常都被吞掉，日志失败 ≠ 功能失败。
/// 3. 自动限量：超过 [_maxRows] 时丢弃最旧的，避免日志无限膨胀撑爆存储。
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';
import '../domain/app_log.dart';

class LogService {
  final Database _db;

  LogService(this._db);

  /// 最多保留多少条
  static const int _maxRows = 2000;

  /// 当前是否已注入数据库（未注入时静默跳过，不影响功能）
  static Database? _injected;

  /// 在 main() 里注入，供静态快捷方法使用
  static void attach(Database db) => _injected = db;

  static LogService? get instance => _injected == null ? null : LogService(_injected!);

  // ---------- 静态快捷入口（业务代码直接调）----------

  /// 信息级
  static Future<void> info(String tag, String message, {String detail = ''}) =>
      _write(LogLevel.info, tag, message, detail);

  /// 警告级（可恢复的异常）
  static Future<void> warning(String tag, String message, {String detail = ''}) =>
      _write(LogLevel.warning, tag, message, detail);

  /// 错误级（明确失败）
  static Future<void> error(String tag, String message, {String detail = ''}) =>
      _write(LogLevel.error, tag, message, detail);

  /// 记录一个异常对象（自动归为 error）
  static Future<void> exception(String tag, String message, Object e, StackTrace? st) =>
      _write(LogLevel.error, tag, message,
          '${e.runtimeType}: $e\n${st?.toString().split('\n').take(6).join('\n') ?? ''}');

  static Future<void> _write(
      LogLevel level, String tag, String message, String detail) async {
    // 同步打到控制台：即使数据库还没就绪，也能用 logcat 看到
    debugPrint('[岁忆/${level.code}] $tag · $message${detail.isEmpty ? '' : '\n$detail'}');
    final db = _injected;
    if (db == null) return;
    try {
      await db.insert(DbSchema.tLogs, {
        'level': level.code,
        'tag': tag,
        'message': message,
        'detail': detail,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await _trim(db);
    } catch (_) {
      // 日志写入失败绝不能影响主流程
    }
  }

  /// 超出上限时删掉最旧的一批
  static Future<void> _trim(Database db) async {
    try {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM ${DbSchema.tLogs}');
      final n = (r.first['c'] as int?) ?? 0;
      if (n <= _maxRows) return;
      await db.rawDelete(
        'DELETE FROM ${DbSchema.tLogs} WHERE id IN ('
        'SELECT id FROM ${DbSchema.tLogs} ORDER BY created_at ASC LIMIT ?)',
        [n - _maxRows],
      );
    } catch (_) {}
  }

  // ---------- 查询（供 UI）----------

  static AppLog _fromRow(Map<String, Object?> r) => AppLog(
        id: r['id'] as int?,
        level: LogLevel.parse((r['level'] as String?) ?? 'info'),
        tag: (r['tag'] as String?) ?? '',
        message: (r['message'] as String?) ?? '',
        detail: (r['detail'] as String?) ?? '',
        createdAt: (r['created_at'] as int?) ?? 0,
      );

  /// 读取日志，[level] 为 null 表示不限等级
  Future<List<AppLog>> recent({
    LogLevel? level,
    int limit = 300,
    String keyword = '',
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (level != null) {
      where.add('level = ?');
      args.add(level.code);
    }
    if (keyword.trim().isNotEmpty) {
      where.add('(message LIKE ? OR tag LIKE ? OR detail LIKE ?)');
      final k = '%${keyword.trim()}%';
      args.addAll([k, k, k]);
    }
    final rows = await _db.query(
      DbSchema.tLogs,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  /// 各等级条数（用于设置页概览）
  Future<Map<LogLevel, int>> countByLevel() async {
    final rows = await _db.rawQuery(
        'SELECT level, COUNT(*) AS c FROM ${DbSchema.tLogs} GROUP BY level');
    final map = {for (final l in LogLevel.values) l: 0};
    for (final r in rows) {
      map[LogLevel.parse(r['level'] as String?)] = (r['c'] as int?) ?? 0;
    }
    return map;
  }

  Future<int> countAll() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM ${DbSchema.tLogs}');
    return (r.first['c'] as int?) ?? 0;
  }

  /// 导出为纯文本（写文件由调用方决定位置）
  Future<String> exportText() async {
    final logs = await recent(limit: 2000);
    final b = StringBuffer()
      ..writeln('岁忆 · 运行日志')
      ..writeln('导出时间：${DateTime.now()}')
      ..writeln('共 ${logs.length} 条')
      ..writeln('-' * 48);
    for (final l in logs) {
      b.writeln('${l.displayTime}  [${l.level.label}]  ${l.tag}');
      b.writeln('  ${l.message}');
      if (l.detail.trim().isNotEmpty) {
        for (final line in l.detail.split('\n')) {
          b.writeln('  | $line');
        }
      }
    }
    return b.toString();
  }

  Future<void> clear() async {
    await _db.delete(DbSchema.tLogs);
  }

  Future<void> clearLevel(LogLevel l) async {
    await _db.delete(DbSchema.tLogs, where: 'level = ?', whereArgs: [l.code]);
  }
}