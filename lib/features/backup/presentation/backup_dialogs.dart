/// 岁忆 · 备份通用对话框（口令输入 / 恢复模式 / 结果展示 / 轻提示）
///
/// 从 settings_page 抽出：settings_page 与 webdav_page 共用同一套交互，
/// 避免两处复制粘贴后行为漂移。
library;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../service/backup_service.dart';

/// 输入备份口令。[confirm] 为 true 时二次确认（用于设置新口令）。
Future<String?> askBackupPassword(
  BuildContext context, {
  bool confirm = false,
  String title = '设置备份口令',
}) async {
  final c1 = TextEditingController();
  final c2 = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SuiyaColors.surface,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: c1,
            obscureText: true,
            decoration: const InputDecoration(hintText: '至少 4 位'),
          ),
          if (confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: c2,
              obscureText: true,
              decoration: const InputDecoration(hintText: '再输一次'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        TextButton(
          onPressed: () {
            if (c1.text.length < 4) return;
            if (confirm && c1.text != c2.text) return;
            Navigator.of(ctx).pop(c1.text);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result;
}

/// 选择恢复方式：合并 / 覆盖
Future<ImportMode?> askImportMode(BuildContext context) =>
    showDialog<ImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: const Text('恢复方式', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.merge),
              title: const Text('合并', style: TextStyle(fontSize: 14)),
              subtitle: const Text('保留现有数据，同一条取较新的',
                  style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.of(ctx).pop(ImportMode.merge),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('覆盖', style: TextStyle(fontSize: 14)),
              subtitle: const Text('清空现有数据后导入',
                  style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.of(ctx).pop(ImportMode.overwrite),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        ],
      ),
    );

/// 展示操作结果（多行摘要）
Future<void> showBackupResult(
        BuildContext context, String title, List<String> lines) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l,
                    style: const TextStyle(
                        fontSize: 13, color: SuiyaColors.inkSoft)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('好')),
        ],
      ),
    );

void showToast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
