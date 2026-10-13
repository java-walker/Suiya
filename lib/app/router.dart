/// 岁忆 · 路由（go_router 声明式）
///
/// 为什么用 go_router 而不是裸 Navigator.pushNamed：
/// 官方维护、支持深链、可声明式做守卫、路由集中一处可审计。
///
/// 重要约定（v1.3.0 踩过的坑）：
/// 本项目**只允许**用 `context.go()` / `context.push()`，
/// 严禁 `Navigator.pushNamed` —— go_router 会接管根 Navigator，
/// 裸 pushNamed 在真机上会静默失败（表现为「点了没反应」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/festival/festival.dart';
import '../features/backup/presentation/settings_page.dart';
import '../features/log/presentation/log_page.dart';
import '../features/place/presentation/place_list_page.dart';
import '../features/record/domain/memory_record.dart';
import '../features/record/presentation/record_editor_page.dart';
import '../features/record/presentation/record_providers.dart';
import '../features/selection/festival_selection_page.dart';
import '../features/timeline/presentation/timeline_page.dart';
import '../features/webdav/presentation/webdav_page.dart';

class Routes {
  static const home = '/';

  /// 真·设置页（数据管理 / 墓园 / 提醒 / 日志 / 回望）
  static const settings = '/settings';

  /// 节日选择（模板页）
  static const festivalSelection = '/festival-selection';

  static const recordNew = '/record/new';
  static const recordEdit = '/record/edit';
  static const places = '/places';
  static const logViewer = '/logs';
  static const webdav = '/webdav';
}

/// 全局路由实例（App 启动时构建一次）
late final GoRouter appRouter = buildRouter();

/// 工厂：测试里可为每个用例建独立实例，避免全局状态污染
GoRouter buildRouter() => GoRouter(
  routes: [
    GoRoute(
      path: Routes.home,
      builder: (context, state) => const TimelinePage(),
    ),
    // v1.3.0 的 bug：这里曾错误地指向 FestivalSelectionHost（模板页），
    // 导致点「设置」进的是模板页。现在指向真正的设置页。
    GoRoute(
      path: Routes.settings,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: Routes.festivalSelection,
      builder: (context, state) => const FestivalSelectionHost(),
    ),
    GoRoute(
      path: Routes.recordNew,
      builder: (context, state) =>
          RecordEditorPage(festival: state.extra as Festival?),
    ),
    GoRoute(
      path: Routes.recordEdit,
      builder: (context, state) =>
          RecordEditorPage(existing: state.extra as MemoryRecord?),
    ),
    GoRoute(
      path: Routes.places,
      builder: (context, state) => const PlaceListPage(),
    ),
    GoRoute(
      path: Routes.logViewer,
      builder: (context, state) => const LogViewerPage(),
    ),
    GoRoute(
      path: Routes.webdav,
      builder: (context, state) => const WebdavPage(),
    ),
  ],
);

/// 模板页包装：直接读 Riverpod 状态，避免层层传参导致状态不同步
class FestivalSelectionHost extends ConsumerWidget {
  const FestivalSelectionHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(selectionProvider);
    return FestivalSelectionPage(
      selection: selection,
      onChanged: (s) =>
          ref.read(selectionProvider.notifier).update(s),
    );
  }
}