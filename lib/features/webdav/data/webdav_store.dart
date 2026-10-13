/// 岁忆 · WebDAV 配置与凭据存取
///
/// 职责分离：
/// - 非敏感配置（服务器/账号/目录/模板/保留份数）→ SharedPreferences（JSON）
/// - WebDAV 密码 → flutter_secure_storage（Android Keystore 加密，绝不明文落盘）
///
/// 桌面测试环境没有 secure storage 平台实现：降级为内存缓存并仅用于测试，
/// 真机永远走 Keystore。
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/storage.dart';
import '../domain/webdav_config.dart';

class WebdavStore {
  static const _kConfig = 'suiya.webdav.v1';
  static const _kPassword = 'suiya.webdav.pass';

  final SuiyaStorage _storage;

  WebdavStore(this._storage);

  FlutterSecureStorage? _secure;

  FlutterSecureStorage get _secureStore =>
      _secure ??= const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );

  // ---------- 配置 ----------

  WebdavConfig? loadConfig() {
    final raw = _storage.getRaw(_kConfig);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WebdavConfig.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConfig(WebdavConfig config) =>
      _storage.setRaw(_kConfig, jsonEncode(config.toJson()));

  // ---------- 密码（Keystore 加密） ----------

  Future<String?> loadPassword() async {
    try {
      return await _secureStore.read(key: _kPassword);
    } catch (_) {
      // 桌面测试/无 Keystore 环境：只回退内存，不落盘
      return _memoryPassword;
    }
  }

  Future<void> savePassword(String password) async {
    try {
      await _secureStore.write(key: _kPassword, value: password);
    } catch (_) {
      _memoryPassword = password;
    }
  }

  /// 内存降级缓存（仅测试环境会走到）
  static String? _memoryPassword;
}
