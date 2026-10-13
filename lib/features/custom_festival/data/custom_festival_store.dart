/// 岁忆 · 自定义日子的数据访问（data 层）
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';
import '../../../core/festival/festival.dart';
import '../domain/custom_festival.dart';

class CustomFestivalStore {
  final Database _db;
  CustomFestivalStore(this._db);

  static CustomFestival _fromRow(Map<String, Object?> r) {
    List<PromptTemplate> prompts = const [];
    try {
      final raw = r['prompts_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        final d = jsonDecode(raw);
        if (d is List) {
          prompts = d
              .whereType<Map>()
              .map((e) {
              final q = e['q'];
              final p = e['p'];
              return PromptTemplate(
                q?.toString() ?? '',
                placeholder: p?.toString(),
              );
            })
              .toList();
        }
      }
    } catch (_) {}
    return CustomFestival(
      id: r['id'] as String,
      name: r['name'] as String,
      recurrence: CustomRecurrence.parse(
          (r['recurrence'] as String?) ?? 'solarAnnual'),
      solarMonth: (r['solar_month'] as num?)?.toInt(),
      solarDay: (r['solar_day'] as num?)?.toInt(),
      lunarMonth: (r['lunar_month'] as num?)?.toInt(),
      lunarDay: (r['lunar_day'] as num?)?.toInt(),
      defaultAdvanceDays: (r['default_advance'] as int?) ?? 1,
      note: r['note'] as String?,
      prompts: prompts,
      sortIndex: (r['sort_index'] as int?) ?? 0,
      anchorYear: (r['anchor_year'] as num?)?.toInt(),
      createdAt: (r['created_at'] as int?) ?? 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
    );
  }

  Future<List<CustomFestival>> all() async {
    final rows = await _db.query(DbSchema.tCustomFestivals,
        orderBy: 'sort_index ASC, created_at ASC');
    return rows.map(_fromRow).toList();
  }

  Future<CustomFestival?> byId(String id) async {
    final rows = await _db.query(DbSchema.tCustomFestivals,
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> save(CustomFestival f) async {
    await _db.insert(DbSchema.tCustomFestivals, {
      'id': f.id,
      'name': f.name,
      'recurrence': f.recurrence.name,
      'solar_month': f.solarMonth,
      'solar_day': f.solarDay,
      'lunar_month': f.lunarMonth,
      'lunar_day': f.lunarDay,
      'default_advance': f.defaultAdvanceDays,
      'note': f.note,
      'prompts_json': jsonEncode(f.prompts
          .map((p) => {'q': p.question, 'p': p.placeholder})
          .toList()),
      'sort_index': f.sortIndex,
      'anchor_year': f.anchorYear,
      'created_at': f.createdAt,
      'updated_at': f.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    await _db.delete(DbSchema.tCustomFestivals,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final r = await _db
        .rawQuery('SELECT COUNT(*) AS c FROM ${DbSchema.tCustomFestivals}');
    return (r.first['c'] as int?) ?? 0;
  }
}