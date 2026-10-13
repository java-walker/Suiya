/// 岁忆 · 导入导出（加密归档 + 明文 JSON）
///
/// 加密格式 `.suiya`：
///   头部(明文 JSON) + 媒体(zip) 一起打包，再用口令派生的密钥 AES-GCM 加密。
///   口令错误或文件损坏时，宁可明确报错，也不要静默导入半份数据。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/db/schema.dart';
import '../../record/data/media_store.dart';

/// 导出结果
class ExportResult {
  final String path;
  final int recordCount;
  final int mediaCount;
  final int placeCount;
  final bool encrypted;

  const ExportResult({
    required this.path,
    required this.recordCount,
    required this.mediaCount,
    required this.placeCount,
    required this.encrypted,
  });
}

/// 导入结果
class ImportResult {
  final int recordsAdded;
  final int recordsUpdated;
  final int placesAdded;
  final int mediaRestored;
  final List<String> warnings;

  const ImportResult({
    required this.recordsAdded,
    required this.recordsUpdated,
    required this.placesAdded,
    required this.mediaRestored,
    required this.warnings,
  });
}

/// 导入模式
enum ImportMode {
  /// 合并：同 id 保留较新的一条
  merge,

  /// 覆盖：清空后导入
  overwrite,
}

class BackupService {
  final Database _db;

  BackupService(this._db);

  // ---------- 导出 ----------

  /// 导出为明文 JSON（结构可读，便于人工检查）
  Future<String> exportPlainJson() async {
    final data = await _dumpAll();
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, '岁忆导出_${_stamp()}.json'));
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return f.path;
  }

  /// 导出为加密归档包
  Future<ExportResult> exportEncrypted(String password) async {
    if (password.length < 4) {
      throw ArgumentError('口令至少 4 位');
    }
    final data = await _dumpAll();
    final mediaRoot = await MediaStore.mediaRoot();

    // 1) 媒体打包成 zip
    final mediaArchive = Archive();
    var mediaCount = 0;
    final mediaDir = Directory(mediaRoot.path);
    if (mediaDir.existsSync()) {
      for (final e in mediaDir.listSync()) {
        if (e is File) {
          final bytes = e.readAsBytesSync();
          mediaArchive.addFile(ArchiveFile(p.basename(e.path), bytes.length, bytes));
          mediaCount++;
        }
      }
    }
    final mediaZip = ZipEncoder().encode(mediaArchive);

    // 2) 组装 payload
    final payload = <String, dynamic>{
      'format': 'suiya.archive',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'data': data,
      'mediaZip': base64Encode(mediaZip ?? const <int>[]),
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));

    // 3) 标准 PBKDF2 派生密钥 + AES-256-GCM 加密
    final salt = _randomBytes(16);
    final secret = await _pbkdf2(password, salt);
    final box = await AesGcm.with256bits().encrypt(
      payloadBytes,
      secretKey: secret,
      nonce: _randomBytes(12),
    );
    final iv = box.nonce;
    final cipherText = box.cipherText;
    final mac = box.mac.bytes;

    // 4) 写文件：MAGIC(8) | salt(16) | iv(12) | mac(16) | ciphertext
    //    AES-GCM 的认证标签是 128 bit = 16 字节（cryptography 包固定值），
    //    导入端必须按 16 切，否则会把密文切坏、MAC 永远校验失败。
    final out = BytesBuilder()
      ..add('SUIYA001'.codeUnits)
      ..add(salt)
      ..add(iv)
      ..add(mac)
      ..add(cipherText);
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, '岁忆备份_${_stamp()}.suiya'));
    await f.writeAsBytes(out.toBytes());

    return ExportResult(
      path: f.path,
      recordCount: (data['records'] as List).length,
      mediaCount: mediaCount,
      placeCount: (data['places'] as List).length,
      encrypted: true,
    );
  }

  // ---------- 导入 ----------

  /// 从加密归档导入
  Future<ImportResult> importEncrypted(String filePath, String password,
      {ImportMode mode = ImportMode.merge}) async {
    final bytes = await File(filePath).readAsBytes();
    // macLen 必须与导出端一致：AES-GCM tag = 16 字节
    const magicLen = 8, saltLen = 16, ivLen = 12, macLen = 16;
    if (bytes.length < magicLen + saltLen + ivLen + macLen) {
      throw const FormatException('文件不完整，可能已损坏');
    }
    final magic = String.fromCharCodes(bytes.sublist(0, magicLen));
    if (magic != 'SUIYA001') {
      throw const FormatException('不是岁忆的备份文件');
    }
    var off = magicLen;
    final salt = bytes.sublist(off, off + saltLen);
    off += saltLen;
    final iv = bytes.sublist(off, off + ivLen);
    off += ivLen;
    final mac = bytes.sublist(off, off + macLen);
    off += macLen;
    final cipherText = bytes.sublist(off);

    final secret = await _pbkdf2(password, salt);
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(mac)),
      secretKey: secret,
    );

    final payload = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return _restore(payload, mode);
  }

  /// 从明文 JSON 导入
  Future<ImportResult> importPlainJson(String filePath,
      {ImportMode mode = ImportMode.merge}) async {
    final raw = await File(filePath).readAsString();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return _restore(data, mode);
  }

  // ---------- 内部 ----------

  Future<Map<String, dynamic>> _dumpAll() async {
    final records = await _db.query(DbSchema.tRecords);
    final places = await _db.query(DbSchema.tPlaces);
    final media = await _db.query(DbSchema.tMedia);
    final customs = await _db.query(DbSchema.tCustomFestivals);
    final presets = await _db.query(DbSchema.tPresets);
    return {
      'records': records,
      'places': places,
      'media': media,
      'custom_festivals': customs,
      'presets': presets,
    };
  }

  Future<ImportResult> _restore(Map<String, dynamic> payload, ImportMode mode) async {
    final warnings = <String>[];
    if (payload['format'] != null && payload['format'] != 'suiya.archive') {
      throw const FormatException('不支持的备份格式');
    }
    final data = (payload['data'] ?? payload) as Map<String, dynamic>;
    final recs = (data['records'] as List?) ?? const [];
    final pls = (data['places'] as List?) ?? const [];
    final med = (data['media'] as List?) ?? const [];
    final customs = (data['custom_festivals'] as List?) ?? const [];
    final presets = (data['presets'] as List?) ?? const [];

    var added = 0, updated = 0, pAdded = 0, mRestored = 0;

    // 媒体 zip（若加密包里有）
    final mediaZipB64 = payload['mediaZip'] as String?;
    if (mediaZipB64 != null && mediaZipB64.isNotEmpty) {
      try {
        final zipBytes = base64Decode(mediaZipB64);
        final archive = ZipDecoder().decodeBytes(zipBytes);
        final root = await MediaStore.mediaRoot();
        for (final f in archive.files) {
          if (!f.isFile) continue;
          final out = File(p.join(root.path, p.basename(f.name)));
          await out.writeAsBytes(f.content as List<int>);
          mRestored++;
        }
      } catch (e) {
        warnings.add('媒体文件恢复失败：$e');
      }
    } else if (med.isNotEmpty) {
      warnings.add('备份中不含媒体文件（${med.length} 条记录仅有路径）');
    }

    // ---- 数据库恢复：整体包在事务里 ----
    // 覆盖模式先清空再逐条插入，中途失败（异常 / App 被杀）若没有事务，
    // 用户旧数据已删、新数据只进来一半，等于永久丢数据。
    final restoredMedia = <String>{};
    await _db.transaction((txn) async {
      if (mode == ImportMode.overwrite) {
        for (final t in [
          DbSchema.tRecords,
          DbSchema.tPlaces,
          DbSchema.tMedia,
          DbSchema.tCustomFestivals,
          DbSchema.tPresets,
        ]) {
          await txn.delete(t);
        }
      }

      // 地点
      for (final r in pls) {
        final row = Map<String, Object?>.from(r as Map);
        final id = row['id'] as String?;
        if (id == null) continue;
        final exists = await txn.query(DbSchema.tPlaces,
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isEmpty) {
          await txn.insert(DbSchema.tPlaces, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          pAdded++;
        } else if (mode == ImportMode.merge) {
          final old = exists.first['updated_at'] as int? ?? 0;
          final neu = row['updated_at'] as int? ?? 0;
          if (neu > old) {
            await txn.update(DbSchema.tPlaces, row,
                where: 'id = ?', whereArgs: [id]);
            pAdded++;
          }
        }
      }

      // 记录
      for (final r in recs) {
        final row = Map<String, Object?>.from(r as Map);
        final id = row['id'] as String?;
        if (id == null) continue;
        final exists = await txn.query(DbSchema.tRecords,
            where: 'id = ?', whereArgs: [id], limit: 1);
        if (exists.isEmpty) {
          await txn.insert(DbSchema.tRecords, row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          added++;
        } else if (mode == ImportMode.merge) {
          final old = exists.first['updated_at'] as int? ?? 0;
          final neu = row['updated_at'] as int? ?? 0;
          if (neu > old) {
            await txn.update(DbSchema.tRecords, row,
                where: 'id = ?', whereArgs: [id]);
            updated++;
          }
        } else {
          updated++;
        }
      }

      // 媒体元数据
      for (final m in med) {
        final row = Map<String, Object?>.from(m as Map);
        if (row['id'] == null) continue;
        await txn.insert(DbSchema.tMedia, row,
            conflictAlgorithm: ConflictAlgorithm.ignore);
        final path = row['path'] as String?;
        if (path != null) restoredMedia.add(p.basename(path));
      }

      // 自定义日子：不恢复的话，换机后所有 custom_ 记录的节日解析为 null，
      // 记录标题还在但节点/日期/农历全部丢失
      for (final c in customs) {
        final row = Map<String, Object?>.from(c as Map);
        if (row['id'] == null) continue;
        await txn.insert(DbSchema.tCustomFestivals, row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // 预设项（同行的人 / 标签）
      for (final pr in presets) {
        final row = Map<String, Object?>.from(pr as Map);
        if (row['id'] == null) continue;
        await txn.insert(DbSchema.tPresets, row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // 覆盖模式：清掉磁盘上已不属于任何恢复记录的旧媒体文件，避免孤儿文件堆积
    if (mode == ImportMode.overwrite) {
      try {
        final root = await MediaStore.mediaRoot();
        for (final e in root.listSync()) {
          if (e is File && !restoredMedia.contains(p.basename(e.path))) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return ImportResult(
      recordsAdded: added,
      recordsUpdated: updated,
      placesAdded: pAdded,
      mediaRestored: mRestored,
      warnings: warnings,
    );
  }

  // ---------- 加密原语（用标准库，避免手写密码学） ----------

  /// PBKDF2-HMAC-SHA256 派生 32 字节密钥（标准做法）
  static Future<SecretKey> _pbkdf2(String password, List<int> salt) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 20000,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String _stamp() {
    final n = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p2(n.month)}${p2(n.day)}_${p2(n.hour)}${p2(n.minute)}';
  }
}
