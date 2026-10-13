/// 岁忆 · 记录编解码（domain 层，纯 Dart，不依赖 Flutter）
///
/// 抽出来是为了让业务规则能在没有 Flutter 引擎的环境里被单测。
library;

import 'dart:convert';

import 'memory_record.dart';

class MemoryCodec {
  /// JSON 字符串数组 -> List<String>，脏数据不崩
  static List<String> splitList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static String dumpList(List<String> list) => jsonEncode(list);

  /// 问答序列化
  static String dumpQa(List<QaItem> qa) => jsonEncode(
        qa.map((e) => {'q': e.question, 'a': e.answer}).toList(),
      );

  static List<QaItem> parseQa(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = jsonDecode(raw);
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => QaItem(
                  e['q']?.toString() ?? '',
                  e['a']?.toString() ?? '',
                ))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
