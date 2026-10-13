/// 岁忆 · 日志实体（domain 层，纯 Dart）
library;

/// 日志等级
enum LogLevel {
  /// 常规运行流水：进入页面、保存成功等
  info,

  /// 异常但可恢复：定位失败、地图未安装、备份文件缺失
  warning,

  /// 明确的失败：保存抛异常、数据库写入失败
  error;

  String get label => switch (this) {
        LogLevel.info => '信息',
        LogLevel.warning => '警告',
        LogLevel.error => '错误',
      };

  String get code => name; // 'info' / 'warning' / 'error'

  static LogLevel parse(String? raw) => LogLevel.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => LogLevel.info,
      );
}

/// 一条日志
class AppLog {
  final int? id;
  final LogLevel level;
  final String tag;
  final String message;
  final String detail;
  final int createdAt;

  const AppLog({
    this.id,
    required this.level,
    this.tag = '',
    required this.message,
    this.detail = '',
    required this.createdAt,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(createdAt);

  /// 形如「10-03 14:22:31」
  String get displayTime {
    final t = time;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}