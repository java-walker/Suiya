/// 岁忆 · WebDAV 云端备份编排
///
/// 编排原则：本类不做加密、不碰数据库——
/// - 加密/明文导出复用 BackupService 既有实现
/// - 恢复复用 BackupService.importEncrypted / importPlainJson
/// 本类只负责「生成 → 传输 → 清理」与结果/警告的汇总。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../backup/service/backup_service.dart';
import '../../log/service/log_service.dart';
import '../../record/presentation/record_providers.dart';
import '../data/webdav_client.dart';
import '../data/webdav_store.dart';
import '../domain/webdav_config.dart';

/// 上传结果
class WebdavUploadResult {
  final String fileName;
  final int bytes;
  final bool encrypted;

  /// 记录/地点条数（供结果弹窗展示）
  final int recordCount;
  final int placeCount;
  final int mediaCount;

  /// 清理旧版本等非致命失败的警告
  final List<String> warnings;

  const WebdavUploadResult({
    required this.fileName,
    required this.bytes,
    required this.encrypted,
    required this.recordCount,
    required this.placeCount,
    required this.mediaCount,
    required this.warnings,
  });
}

class WebdavBackupService {
  final BackupService _backup;
  final WebdavStore _store;

  WebdavBackupService(this._backup, this._store);

  WebdavClient clientFor(WebdavConfig config, String password) =>
      WebdavClient(config: config, password: password);

  /// 上传备份（加密/明文由 config.encryptEnabled 决定）
  ///
  /// [password] 为**备份口令**（加密模式的加密密钥来源），
  /// 与 WebDAV 账号密码是两个东西，后者从 [WebdavStore] 取。
  Future<WebdavUploadResult> upload(
      WebdavConfig config, String? password) async {
    final webdavPassword = await _store.loadPassword();
    if (webdavPassword == null || webdavPassword.isEmpty) {
      throw WebdavException('请先填写并保存 WebDAV 密码');
    }
    final fileName = buildFileName(
      config.fileNameTemplate,
      DateTime.now(),
      encrypted: config.encryptEnabled,
    );
    final warnings = <String>[];

    // 1) 生成本地备份
    Uint8List payloadBytes;
    var recordCount = 0, placeCount = 0, mediaCount = 0;
    if (config.encryptEnabled) {
      if (password == null || password.isEmpty) {
        throw WebdavException('加密备份需要先设置备份口令');
      }
      final r = await _backup.exportEncrypted(password);
      payloadBytes = await File(r.path).readAsBytes();
      recordCount = r.recordCount;
      placeCount = r.placeCount;
      mediaCount = r.mediaCount;
      // 内容将上传云端，删掉临时文件避免私有目录堆积
      try {
        File(r.path).deleteSync();
      } catch (_) {}
    } else {
      final path = await _backup.exportPlainJson();
      payloadBytes = await File(path).readAsBytes();
      warnings.add('明文备份不含照片，且内容网盘服务商可见');
      // 内容将上传云端，删掉临时文件避免私有目录堆积
      try {
        File(path).deleteSync();
      } catch (_) {}
    }

    // 2) 传输
    final client = clientFor(config, webdavPassword);
    try {
      await client.mkcolRecursive(config.remoteDir);
      await client.putBytes(config.remoteDir, fileName, payloadBytes);

      // 3) 多版本清理（best-effort，失败不影响上传结果）
      try {
        final removed = await _pruneOldVersions(client, config);
        if (removed.isNotEmpty) {
          LogService.info('WebDAV', '已清理 ${removed.length} 个旧版本',
              detail: removed.join(', '));
        }
      } catch (e) {
        warnings.add('旧版本清理失败：$e');
        LogService.warning('WebDAV', '旧版本清理失败', detail: '$e');
      }
    } finally {
      client.close();
    }

    LogService.info('WebDAV',
        '已上传备份「$fileName」（${config.encryptEnabled ? '加密' : '明文'}）',
        detail: '${config.remoteDir}/$fileName, '
            '${(payloadBytes.length / 1024).toStringAsFixed(0)} KB');

    return WebdavUploadResult(
      fileName: fileName,
      bytes: payloadBytes.length,
      encrypted: config.encryptEnabled,
      recordCount: recordCount,
      placeCount: placeCount,
      mediaCount: mediaCount,
      warnings: warnings,
    );
  }

  /// 列出云端可用版本（.suiya/.json，按时间倒序）
  Future<List<WebdavFile>> listRemote(WebdavConfig config) async {
    final webdavPassword = await _store.loadPassword();
    if (webdavPassword == null || webdavPassword.isEmpty) {
      throw WebdavException('请先填写并保存 WebDAV 密码');
    }
    final client = clientFor(config, webdavPassword);
    try {
      final all = await client.propFind(config.remoteDir);
      return all
          .where((f) =>
              f.name.toLowerCase().endsWith('.suiya') ||
              f.name.toLowerCase().endsWith('.json'))
          .toList();
    } finally {
      client.close();
    }
  }

  /// 从云端恢复
  ///
  /// [backupPassword] 为备份口令（仅加密 .suiya 需要）。
  Future<ImportResult> restore(
    WebdavConfig config,
    String fileName,
    String? backupPassword,
    ImportMode mode,
  ) async {
    final webdavPassword = await _store.loadPassword();
    if (webdavPassword == null || webdavPassword.isEmpty) {
      throw WebdavException('请先填写并保存 WebDAV 密码');
    }
    final client = clientFor(config, webdavPassword);
    try {
      final bytes = await client.getFile(config.remoteDir, fileName);
      final dir = await getApplicationDocumentsDirectory();
      final tmp = File('${dir.path}${Platform.pathSeparator}webdav_restore_$fileName');
      await tmp.writeAsBytes(bytes);
      try {
        LogService.info('WebDAV', '开始恢复云端备份「$fileName」');
        final lower = fileName.toLowerCase();
        if (lower.endsWith('.suiya')) {
          if (backupPassword == null || backupPassword.isEmpty) {
            throw WebdavException('该备份已加密，请输入备份口令');
          }
          return await _backup.importEncrypted(tmp.path, backupPassword,
              mode: mode);
        }
        return await _backup.importPlainJson(tmp.path, mode: mode);
      } finally {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  /// 超量清理：全部备份文件（不分加密/明文）按时间保留最近 keepCount 份
  Future<List<String>> _pruneOldVersions(
      WebdavClient client, WebdavConfig config) async {
    final all = await client.propFind(config.remoteDir);
    final backups = all
        .where((f) =>
            f.name.toLowerCase().endsWith('.suiya') ||
            f.name.toLowerCase().endsWith('.json'))
        .toList(); // propFind 已按时间倒序
    final toDelete = <String>[];
    for (var i = config.keepCount; i < backups.length; i++) {
      toDelete.add(backups[i].name);
    }
    for (final name in toDelete) {
      await client.delete(config.remoteDir, name);
    }
    return toDelete;
  }
}

final webdavStoreProvider = Provider<WebdavStore>(
    (ref) => WebdavStore(ref.watch(storageProvider)));

final webdavBackupServiceProvider = Provider<WebdavBackupService>(
    (ref) => WebdavBackupService(
        ref.watch(backupServiceProvider), ref.watch(webdavStoreProvider)));
