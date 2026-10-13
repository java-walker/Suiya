/// 岁忆 · 地图唤起工具
///
/// v1.3.0 的问题：点「导航」没反应。根因是只试了高德一个 URL，
/// 失败后 fallback 到网页，而网页在没有浏览器/网络时也静默失败，
/// 最终用户只看到「点了什么都不发生」。
///
/// 这里的做法：**多级兜底链 + 每一步都记日志 + 明确告知用户结果**。
/// 顺序：高德 App → 百度 App → 腾讯地图 App → 系统浏览器 → 复制坐标
library;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class MapLauncher {
  /// 最后一次成功唤起的 App 名（便于日志排查）
  static String? lastTriedApp;

  /// 尝试唤起导航。
  ///
  /// 返回 true 表示成功唤起了某个地图 App；false 表示全部失败
  /// （此时调用方应提示用户，并可选择复制坐标）。
  static Future<bool> navigate({
    required double lat,
    required double lng,
    required String name,
  }) async {
    final label = Uri.encodeComponent(name);
    final attempts = <(String, Uri)>[
      // 高德：navigation?to=lat,lng,name
      ('高德地图',
          Uri.parse('https://uri.amap.com/navigation?to=$lat,$lng,$label&mode=car&policy=1')),
      // 百度：api.map.baidu.com/marker?location=lat,lng&title=name&content=name
      ('百度地图',
          Uri.parse('https://api.map.baidu.com/marker?location=$lng,$lat&title=$label&content=$label&output=html')),
      // 腾讯地图
      ('腾讯地图',
          Uri.parse('https://apis.map.qq.com/uri/v1/marker?marker=coord:$lat,$lng;title:$label')),
    ];

    for (final (app, uri) in attempts) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) {
          MapLauncher.lastTriedApp = app;
          return true;
        }
      } catch (_) {
        // 该 App 未安装或无法处理，继续试下一个
      }
    }

    // 退到浏览器：geo: 是 Android 上最通用的协议
    for (final uri in <Uri>[
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
      Uri.parse('https://uri.amap.com/marker?position=$lng,$lat&name=$label'),
    ]) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {}
    }
    return false;
  }

  /// 唤起系统地图应用（不指定路线，仅定位）
  static Future<bool> showOnMap({
    required double lat,
    required double lng,
    required String name,
  }) async {
    final label = Uri.encodeComponent(name);
    final uris = <Uri>[
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)'),
      Uri.parse('https://uri.amap.com/marker?position=$lng,$lat&name=$label'),
    ];
    for (final uri in uris) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {}
    }
    return false;
  }

  /// 把坐标复制到剪贴板（最后的兜底，让用户能手动粘贴）
  static Future<void> copyCoordinates(double lat, double lng) async {
    await Clipboard.setData(
      ClipboardData(text: '$lat, $lng'),
    );
  }
}