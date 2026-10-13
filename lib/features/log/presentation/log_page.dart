/// 岁忆 · 日志查看页
///
/// 三个等级：信息 / 警告 / 错误。支持按等级筛选、搜索、清空、导出。
/// 这是排查「点了没反应」这类静默失败的唯一手段。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme.dart';
import '../../log/domain/app_log.dart';
import '../../log/service/log_service.dart';
import '../../record/presentation/record_providers.dart';

class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key});

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  LogLevel? _level;
  String _keyword = '';
  bool _loading = true;
  List<AppLog> _logs = const [];
  Map<LogLevel, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final svc = LogService(ref.read(databaseProvider));
    final logs = await svc.recent(level: _level, keyword: _keyword);
    final counts = await svc.countByLevel();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _counts = counts;
      _loading = false;
    });
  }

  Future<void> _export() async {
    try {
      final svc = LogService(ref.read(databaseProvider));
      final text = await svc.exportText();
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/suiya-logs-${DateTime.now().millisecondsSinceEpoch}.txt');
      await f.writeAsString(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出到 ${f.path.split(Platform.pathSeparator).last}')),
      );
      LogService.info('日志', '已导出日志', detail: f.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: Text(_level == null ? '清空全部日志' : '清空「${_level!.label}」日志',
            style: const TextStyle(fontSize: 16)),
        content: const Text('此操作不可撤销。',
            style: TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = LogService(ref.read(databaseProvider));
    if (_level == null) {
      await svc.clear();
    } else {
      await svc.clearLevel(_level!);
    }
    await _load();
    ref.invalidate(logCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final total = _counts.values.fold<int>(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
            tooltip: '刷新',
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export') _export();
              if (v == 'clear') _confirmClear();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('导出为文本文件')),
              PopupMenuItem(value: 'clear', child: Text('清空日志')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _levelBar(total),
          _searchBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _logs.isEmpty
                    ? const _empty()
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _logs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _LogTile(log: _logs[i]),
                      ),
          ),
        ],
      ),
    );
  }

  /// 等级筛选栏：全部 / 信息 / 警告 / 错误，角标显示条数
  Widget _levelBar(int total) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(null, '全部', total),
          for (final l in LogLevel.values) _chip(l, l.label, _counts[l] ?? 0),
        ],
      ),
    );
  }

  Widget _chip(LogLevel? l, String label, int n) {
    final on = _level == l;
    final color = _levelColor(l);
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: FilterChip(
        label: Text('$label $n',
            style: TextStyle(fontSize: 12, color: on ? color : SuiyaColors.inkSoft)),
        selected: on,
        onSelected: (_) {
          setState(() => _level = on ? null : l);
          _load();
        },
        selectedColor: color.withOpacity(0.12),
        checkmarkColor: color,
        side: on ? BorderSide(color: color.withOpacity(0.4)) : null,
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: TextField(
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索日志内容、标签…',
          hintStyle: const TextStyle(fontSize: 13, color: SuiyaColors.inkFaint),
          isDense: true,
          filled: true,
          fillColor: SuiyaColors.paperDeep,
          prefixIcon: const Icon(Icons.search, size: 18, color: SuiyaColors.inkFaint),
          suffixIcon: _keyword.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    setState(() => _keyword = '');
                    _load();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) => setState(() => _keyword = v),
        onSubmitted: (_) => _load(),
      ),
    );
  }

  static Color _levelColor(LogLevel? l) => switch (l) {
        LogLevel.error => SuiyaColors.cinnabar,
        LogLevel.warning => SuiyaColors.ochre,
        LogLevel.info => SuiyaColors.moss,
        null => SuiyaColors.inkSoft,
      };
}

class _LogTile extends StatelessWidget {
  final AppLog log;
  const _LogTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = _LogViewerPageState._levelColor(log.level);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      leading: Container(
        width: 4,
        height: 34,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      title: Row(
        children: [
          Text(log.displayTime,
              style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(log.level.label,
                style: TextStyle(fontSize: 10, color: color)),
          ),
          if (log.tag.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(log.tag,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(log.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: SuiyaColors.ink)),
      ),
      children: log.detail.trim().isEmpty
          ? const []
          : [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SuiyaColors.paperDeep,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  log.detail,
                  style: const TextStyle(
                      fontSize: 11, color: SuiyaColors.inkSoft, height: 1.5),
                ),
              ),
            ],
    );
  }
}

class _empty extends StatelessWidget {
  const _empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 44, color: SuiyaColors.inkFaint),
              const SizedBox(height: 12),
              const Text('暂无日志',
                  style: TextStyle(fontSize: 15, color: SuiyaColors.ink)),
              const SizedBox(height: 6),
              const Text('正常使用时的操作会记在这里\n出问题时可导出后反馈',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
            ],
          ),
        ),
      );
}