// 复现 timeline_page.dart 的 _buildNodes() 逻辑，纯 Dart 不依赖 Flutter
import 'package:suiya/core/festival/festival.dart';
import 'package:suiya/core/lunar/lunar_engine.dart';

void main() {
  final selection = FestivalSelection.defaultSelection();
  print('默认模板 enabled 数量: ${selection.enabled.length}');
  print('模板名: ${Templates.traditional.name}');
  print('enabled keys: ${selection.enabled.keys.toList()}');

  final now = DateTime.now();
  final year = now.year;
  print('\n当前时间: $now  目标年份: $year');

  // 复现 _buildNodes
  final festivals = <Festival>[];
  for (final id in selection.enabled.keys) {
    final f = Festivals.byId(id) ??
        Festivals.allTerms().where((e) => e.id == id).firstOrNull;
    if (f != null) {
      festivals.add(f);
      print('  解析 OK: $id -> ${f.name} (${f.recurrence})');
    } else {
      print('  !! 解析失败(被丢弃): $id');
    }
  }

  print('\n成功解析节日数: ${festivals.length}');

  final nodes = <String>[];
  for (final f in festivals) {
    if (f.recurrence == RecurrenceType.lunarMonthly) {
      final lunarYear = LunarEngine.solarToLunar(now.year, now.month, now.day).year;
      for (var ly = lunarYear; ly <= lunarYear + 1; ly++) {
        final d = LunarEngine.lunarToSolar(ly, f.lunarMonth ?? 1, f.lunarDay ?? 1);
        if (d.year < year || d.year > year) continue;
        nodes.add('${f.name} ${d.month}/${d.day}');
      }
    } else {
      try {
        final d = f.dateIn(year);
        if (d == null) {
          print('  !! dateIn($year) 返回 null: ${f.name}');
          continue;
        }
        nodes.add('${f.name} ${d.month}/${d.day}');
      } catch (e) {
        print('  !! dateIn 抛异常: ${f.name} -> $e');
      }
    }
  }

  print('\n时间轴节点数: ${nodes.length}');
  for (final n in nodes.take(20)) {
    print('   $n');
  }

  // 顺便验证"下一个日子"卡片
  final today = DateTime(now.year, now.month, now.day);
  print('\n=== 下一个日子卡片检查 ===');
  if (nodes.isEmpty) {
    print('  !! 节点为空 -> 首页显示空状态页（"还没有选择任何日子"）');
  } else {
    print('  卡片可显示');
  }
}
