/// 岁忆 · 岁有佳节，忆有归处
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'app/router.dart';
import 'core/festival/festival.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'features/custom_festival/data/custom_festival_store.dart';
import 'features/custom_festival/domain/custom_festival.dart';
import 'features/log/service/log_service.dart';
import 'features/record/data/media_store.dart';
import 'features/record/data/memory_repository_impl.dart';
import 'features/record/domain/memory_record.dart';
import 'features/record/presentation/record_providers.dart';
import 'features/reminder/service/reminder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await SuiyaStorage.open();
  final repository = await SqfliteMemoryRepository.open();

  // 日志系统必须在任何业务动作之前就位，否则早期失败无从追查
  LogService.attach(repository.db);

  // 自定义节日存在 SQLite 里，但 SharedPreferences 只存 id 字符串。
  // 必须在读取「勾选了哪些日子」之前把 custom id 注册进 SuiyaStorage，
  // 否则冷启动会把它们当成已不存在的节日过滤掉（v1.4.0 的真实 bug）。
  final customs = await _loadCustoms(repository.db);
  SuiyaStorage.registerKnownIds(customs.map((c) => c.id));

  // 注入节日解析器：让 domain 层能算出公历日期，同时保持 domain 零 festival 依赖。
  // 顺序与 resolveFestival 一致：内置 → 二十四节气 → 自定义。
  MemoryRecord.bindFestivalResolver((id, year) {
    final builtin = Festivals.byId(id);
    if (builtin != null) return builtin.dateIn(year);
    for (final t in Festivals.allTerms()) {
      if (t.id == id) return t.dateIn(year);
    }
    for (final c in customs) {
      if (c.id == id) return c.dateIn(year);
    }
    return null;
  });

  // 预热媒体根目录缓存（详情弹窗里的照片要靠它拼绝对路径）
  try {
    await MediaStore.ensureMediaRoot();
  } catch (e) {
    debugPrint('媒体目录初始化失败: $e');
  }

  // 提醒服务初始化（时区数据 + 通知插件）
  try {
    await ReminderService.init();
  } catch (e) {
    LogService.warning('启动', '提醒服务初始化失败', detail: '$e');
  }

  LogService.info('启动', '岁忆已启动', detail: '数据库版本已就绪，'
      '媒体目录已预热，自定义节日 ${customs.length} 个');

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        memoryRepositoryProvider.overrideWithValue(repository),
        databaseProvider.overrideWithValue(repository.db),
        // 启动快照，避免首帧再查一次库，也让 resolver 与它保持一致
        customFestivalsSnapshotProvider
            .overrideWith((ref) => List<CustomFestival>.from(customs)),
      ],
      child: const SuiyaApp(),
    ),
  );
}

/// 读取全部自定义节日；失败只记录日志，不阻塞启动
Future<List<CustomFestival>> _loadCustoms(Database db) async {
  try {
    return await CustomFestivalStore(db).all();
  } catch (e) {
    debugPrint('自定义节日加载失败: $e');
    LogService.exception('启动', '自定义节日加载失败', e, null);
    return const <CustomFestival>[];
  }
}

class SuiyaApp extends StatelessWidget {
  const SuiyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '岁忆',
      debugShowCheckedModeBanner: false,
      theme: SuiyaTheme.light(),
      routerConfig: appRouter,
    );
  }
}