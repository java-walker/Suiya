/// 岁忆 · 提醒服务
///
/// 设计要点：
/// 1. 提醒按 [advanceDays] 提前触发，节日类型默认值来自节日库
/// 2. 通知文案按类型生成（"明天清明，该上山了 · 墓园在XX"）
/// 3. 时区/农历跨年变化后重算
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../record/domain/memory_record.dart';

/// 提醒服务
class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// 初始化（App 启动时调一次）
  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await _localTz()));
    } catch (_) {
      // 时区数据失败不致命，回落到 UTC
      try {
        tzdata.initializeTimeZones();
      } catch (_) {}
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: android);
    try {
      await _plugin.initialize(init);
      _ready = true;
    } catch (e) {
      debugPrint('提醒初始化失败: $e');
    }
  }

  static Future<String> _localTz() async {
    // 避免额外依赖，直接用 UTC+8 近似（国内无夏令时）
    return 'Asia/Shanghai';
  }

  /// 请求通知权限（Android 13+ 需要）
  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final ok = await android.requestNotificationsPermission();
        return ok ?? true;
      }
    } catch (e) {
      debugPrint('请求通知权限失败: $e');
    }
    return false;
  }

  /// 是否已授权
  static Future<bool> hasPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 为某条记录安排提醒
  ///
  /// 返回实际触发时间（毫秒），无法安排则返回 null。
  static Future<int?> scheduleFor(MemoryRecord r, {int? advanceDays}) async {
    final date = r.solarDate;
    if (date == null || !r.remindOn) return null;

    final days = advanceDays ?? r.advanceDays;
    final fire = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: days))
        .add(const Duration(hours: 9)); // 早上 9 点提醒
    if (fire.isBefore(DateTime.now())) return null;

    await init();
    if (!_ready) return null;

    final id = r.id.hashCode & 0x7fffffff;
    try {
      await _plugin.zonedSchedule(
        id,
        titleForAdvance(days),
        body(r, days),
        tz.TZDateTime.from(fire, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'suiya_reminder',
            '岁时提醒',
            channelDescription: '清明、中秋等岁时的提前提醒',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: null,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return fire.millisecondsSinceEpoch;
    } catch (e) {
      debugPrint('安排提醒失败: $e');
      return null;
    }
  }

  /// 通知标题（按实际提前天数生成）
  ///
  /// 不要在「调度时刻」用 DateTime.now() 算相对时间——那会被固化进通知，
  /// 提前 90 天创建的记录触发时仍显示「90 天后」。
  static String titleForAdvance(int advanceDays) {
    if (advanceDays <= 0) return '就是今天';
    if (advanceDays == 1) return '明天';
    return '$advanceDays 天后';
  }

  /// 通知正文：按类型生成，带地点信息
  static String body(MemoryRecord r, int advanceDays) {
    final parts = <String>[];
    if (r.address != null && r.address!.isNotEmpty) {
      parts.add('在${r.address}');
    } else if (r.placeId != null) {
      parts.add('在老地方');
    }
    final who = r.participants.isEmpty ? '' : '和${r.participants.join('、')}';
    final prefix = who.isEmpty ? '' : '$who，';
    final suffix = parts.isEmpty ? '' : ' · ${parts.first}';
    return '$prefix该记一笔了$suffix';
  }

  /// 取消某条记录的提醒
  static Future<void> cancel(String recordId) async {
    try {
      await _plugin.cancel(recordId.hashCode & 0x7fffffff);
    } catch (_) {}
  }

  /// 取消全部（重算前用）
  static Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// 列出未来 N 天待提醒的记录（首页用）
  static Future<List<MemoryRecord>> upcoming(
      List<MemoryRecord> all, {
      int withinDays = 30,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final res = all.where((r) {
      if (!r.remindOn) return false;
      final d = r.solarDate;
      if (d == null) return false;
      final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
      return diff >= 0 && diff <= withinDays;
    }).toList()
      ..sort((a, b) => (a.solarDate ?? DateTime(2100)).compareTo(b.solarDate ?? DateTime(2100)));
    return res;
  }
}
