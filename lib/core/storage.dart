/// 岁忆 · 本地存储
///
/// 用户的「选了哪些日子」「哪些日子已经记录过」必须跨进程保存，
/// 否则每次杀 App 都要重来一遍——这是记录类 App 的底线。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'festival/festival.dart';

/// 记录按「年 + 节日 id」维度存：2026 中秋记过，不等于 2027 中秋记过。
class SuiyaStorage {
  SuiyaStorage._(this._prefs);

  final SharedPreferences _prefs;

  static const _kSelection = 'suiya.selection.v1';
  static const _kSelectionInitialized = 'suiya.selection.initialized';
  static String _kRecords(int year) => 'suiya.records.v1.$year';

/// 额外认可的节日 id —— 目前只有用户自定义节日（custom_ 前缀）。
  ///
  /// v1.4.0 之前的 [_festivalExists] 只认内置节日与二十四节气，
  /// 导致自定义节日的勾选状态在冷启动后被当成脏数据过滤掉，
  /// 表现为「重启后自定义节日消失 / 变成未勾选」。
  /// 自定义节日存在 SQLite 里，SharedPreferences 层无从查询，
  /// 因此由 main() 在读取选择前把已知的 custom id 注入进来。
  static final Set<String> extraKnownIds = <String>{};

  /// 注入自定义节日 id（应在 runApp 之前调用）
  static void registerKnownIds(Iterable<String> ids) {
    extraKnownIds
      ..clear()
      ..addAll(ids);
  }

  static Future<SuiyaStorage> open() async =>
      SuiyaStorage._(await SharedPreferences.getInstance());

  // ---------- 选择了哪些日子 ----------

  /// 读取已勾选的节日；[fallback] 用于首次启动（默认传统模板）。
  ///
  /// 「从未选择过」与「用户显式全部取消」必须区分：
  /// 否则 disableAll() 存下的空选择在冷启动后被当成首次启动，
  /// 14 个传统节日全部悄悄恢复勾选并重新开始提醒。
  FestivalSelection loadSelection(FestivalSelection fallback) {
    final initialized = _prefs.getBool(_kSelectionInitialized) ?? false;
    final raw = _prefs.getString(_kSelection);
    if (raw == null || raw.isEmpty) {
      return initialized ? FestivalSelection.empty() : fallback;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return initialized ? FestivalSelection.empty() : fallback;
      }
      final map = <String, int?>{};
      decoded.forEach((k, v) {
        if (k is String) map[k] = v is int ? v : null;
      });
      if (map.isEmpty) {
        return initialized ? FestivalSelection.empty() : fallback;
      }
      // 过滤掉已不存在的节日 id，防止版本更新后残留脏数据
      final valid = <String, int?>{};
      for (final entry in map.entries) {
        if (_festivalExists(entry.key)) valid[entry.key] = entry.value;
      }
      if (valid.isEmpty) {
        return initialized ? FestivalSelection.empty() : fallback;
      }
      return FestivalSelection(valid);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> saveSelection(FestivalSelection selection) async {
    final map = <String, int?>{...selection.enabled};
    await _prefs.setString(_kSelection, jsonEncode(map));
    // 一旦写过选择，「空选择」就代表用户显式全关，而不是首次启动
    await _prefs.setBool(_kSelectionInitialized, true);
  }

  // ---------- 通用键值（feature 模块自己的轻量配置，如 WebDAV） ----------

  /// 特性模块的轻量配置直接以「模块前缀 key + JSON 字符串」存这里，
  /// 避免每个小配置都建一张表。序列化/校验由模块自己的 Store 负责。
  String? getRaw(String key) => _prefs.getString(key);

  Future<void> setRaw(String key, String value) =>
      _prefs.setString(key, value);

  // ---------- 哪些日子已记录 ----------

  /// 读取某年已记录的节日 id 集合
  Set<String> loadRecords(int year) {
    final raw = _prefs.getString(_kRecords(year));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> saveRecords(int year, Set<String> ids) async {
    final list = ids.toList()..sort();
    await _prefs.setString(_kRecords(year), jsonEncode(list));
  }

  static bool _festivalExists(String id) {
    if (extraKnownIds.contains(id)) return true;
    if (Festivals.byId(id) != null) return true;
    return Festivals.allTerms().any((e) => e.id == id);
  }
}
