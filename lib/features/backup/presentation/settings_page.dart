/// 岁忆 · 设置与数据管理
///
/// 入口：节日选择 / 墓园管理 / 提醒权限 / 导入导出 / 主题 / 年度回望
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme.dart';
import '../../log/domain/app_log.dart';
import '../../record/presentation/record_providers.dart';
import '../../reminder/service/reminder_service.dart';
import '../service/backup_service.dart';
import '../../review/presentation/year_review_page.dart';
import 'backup_dialogs.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _section('记录'),
          _tile(Icons.edit_calendar_outlined, '选择你在意的日子', '时间轴上显示哪些节日', () {
            // v1.3.0 用了 Navigator.pushNamed —— 在 go_router 下会静默失败
            context.push('/festival-selection');
          }),
          _tile(Icons.place_outlined, '墓园与常去的地方', '记地点、一键导航', () {
            context.push('/places');
          }),
          _tile(Icons.auto_graph_outlined, '年度回望', '看看这一年记了多少', () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const YearReviewPage()),
            );
          }),

          _section('提醒'),
          _tile(Icons.notifications_outlined, '通知权限', '检查与开启', () async {
            final has = await ReminderService.hasPermission();
            if (!context.mounted) return;
            if (has) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('通知权限已开启')),
              );
            } else {
              final ok = await ReminderService.requestPermission();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? '已开启通知' : '未获得通知权限，可在系统设置里手动开启'),
                ),
              );
            }
          }),

          _section('数据'),
          _tile(Icons.backup_outlined, '导出加密备份', '口令加密，含照片', () => _exportEncrypted(context, ref)),
          _tile(Icons.file_download_outlined, '导出明文 JSON', '结构可读，便于检查', () => _exportPlain(context, ref)),
          _tile(Icons.restore_outlined, '从备份恢复', '选择 .suiya 或 .json', () => _import(context, ref)),
          _tile(Icons.cloud_upload_outlined, 'WebDAV 云备份', '坚果云 / Nextcloud / Alist / 群晖 / 自定义', () {
            context.push('/webdav');
          }),

          _section('排查'),
          const _LogOverview(),
          _tile(Icons.bug_report_outlined, '打开全部日志', '信息 / 警告 / 错误', () {
            context.push('/logs');
          }),

          _section('关于'),
          _aboutTile(),
        ],
      ),
    );
  }

  Future<void> _exportEncrypted(BuildContext context, WidgetRef ref) async {
    final pwd = await _askPassword(context, confirm: true);
    if (pwd == null || !context.mounted) return;
    try {
      final svc = ref.read(backupServiceProvider);
      final r = await svc.exportEncrypted(pwd);
      if (!context.mounted) return;
      await _showResult(context, '备份完成', [
        '文件：${r.path.split(Platform.pathSeparator).last}',
        '记录 ${r.recordCount} 条',
        '地点 ${r.placeCount} 个',
        '照片 ${r.mediaCount} 张',
        '请牢记口令，忘记无法恢复',
      ]);
    } catch (e) {
      if (context.mounted) _toast(context, '导出失败：$e');
    }
  }

  Future<void> _exportPlain(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref.read(backupServiceProvider).exportPlainJson();
      if (!context.mounted) return;
      await _showResult(context, '导出完成', ['文件：${path.split(Platform.pathSeparator).last}']);
    } catch (e) {
      if (context.mounted) _toast(context, '导出失败：$e');
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // 从 App 私有目录列出可用的备份文件
    final Directory docs;
    try {
      docs = await getApplicationDocumentsDirectory();
    } catch (_) {
      if (context.mounted) _toast(context, '无法访问存储目录');
      return;
    }

    final files = docs
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.suiya') || f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    if (!context.mounted) return;
    if (files.isEmpty) {
      _toast(context, '还没有备份文件');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SuiyaColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要恢复的备份',
                  style: TextStyle(fontSize: 15, color: SuiyaColors.ink)),
            ),
            for (final f in files.take(20))
              ListTile(
                title: Text(f.path.split(Platform.pathSeparator).last,
                    style: const TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _doImport(context, ref, f.path);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _doImport(BuildContext context, WidgetRef ref, String path) async {
    final isEnc = path.endsWith('.suiya');
    String? pwd;
    if (isEnc) {
      pwd = await _askPassword(context, confirm: false, title: '输入备份口令');
      if (pwd == null || !context.mounted) return;
    }
    final mode = await _askMode(context);
    if (mode == null || !context.mounted) return;

    try {
      final svc = ref.read(backupServiceProvider);
      final r = isEnc
          ? await svc.importEncrypted(path, pwd!, mode: mode)
          : await svc.importPlainJson(path, mode: mode);
      // 刷新界面：不能只刷 records/places —— timelineProvider 直接 watch
      // 仓储，yearReviewProvider watch recordsOfYear，都不跟随 recordsProvider
      // 重建，恢复后首页会显示导入前的旧数据
      ref.invalidate(recordsProvider);
      ref.invalidate(placesProvider);
      final y = DateTime.now().year;
      ref.invalidate(recordsOfYearProvider(y));
      ref.invalidate(timelineProvider(y));
      ref.invalidate(yearReviewProvider(y));
      // 备份里带回了自定义日子：重建快照、knownIds 与解析器
      await ref.read(customFestivalActionsProvider).refreshFromDb();
      if (!context.mounted) return;
      await _showResult(context, '恢复完成', [
        '新增记录 ${r.recordsAdded} 条',
        '更新记录 ${r.recordsUpdated} 条',
        '地点 ${r.placesAdded} 个',
        '照片 ${r.mediaRestored} 张',
        for (final w in r.warnings) '注意：$w',
      ]);
    } on FormatException catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, '恢复失败：$e');
    }
  }
}

Future<String?> _askPassword(BuildContext context,
        {bool confirm = false, String title = '设置备份口令'}) =>
    askBackupPassword(context, confirm: confirm, title: title);

Future<ImportMode?> _askMode(BuildContext context) => askImportMode(context);

Future<void> _showResult(
        BuildContext context, String title, List<String> lines) =>
    showBackupResult(context, title, lines);

void _toast(BuildContext context, String msg) => showToast(context, msg);

/// 日志概览：直接在设置页显示三级日志条数（排查问题时一眼看到有没有错误）
class _LogOverview extends ConsumerWidget {
  const _LogOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(logCountsProvider);
    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (counts) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
        child: Row(
          children: [
            _pill('信息', counts[LogLevel.info] ?? 0, SuiyaColors.moss),
            const SizedBox(width: 8),
            _pill('警告', counts[LogLevel.warning] ?? 0, SuiyaColors.ochre),
            const SizedBox(width: 8),
            _pill('错误', counts[LogLevel.error] ?? 0, SuiyaColors.cinnabar),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('$label $n', style: TextStyle(fontSize: 11, color: color)),
      );
}

/// 分组标题
Widget _section(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
    );

/// 设置项
Widget _tile(IconData icon, String title, String? sub, VoidCallback onTap) =>
    ListTile(
      leading: Icon(icon, size: 21, color: SuiyaColors.inkSoft),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12)),
      trailing:
          const Icon(Icons.chevron_right, size: 18, color: SuiyaColors.inkFaint),
      onTap: onTap,
    );

/// 关于
Widget _aboutTile() => const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('岁忆 v1.5.1',
              style: TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
          SizedBox(height: 4),
          Text('数据全部存在本机，卸载即消失。请定期导出备份。',
              style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
        ],
      ),
    );