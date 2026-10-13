/// 岁忆 · WebDAV 客户端（dart:io 手写，零第三方 HTTP 依赖）
///
/// 只实现备份需要的 5 个方法：PROPFIND / MKCOL / PUT / GET / DELETE。
///
/// 为什么不用 webdav_client 包：避免引入 http 依赖链与 AGP 8.11 垫片适配面，
/// 且本项目只需要最小方法集，~200 行手写更可控。
///
/// 安全：Basic Auth（凭据仅在请求头，TLS 传输）；口令/密码不进任何日志。
/// 证书：默认严格校验，`ignoreCert` 为自签证书场景的显式开关。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../domain/webdav_config.dart';

/// 云端一个备份文件
class WebdavFile {
  final String name;
  final DateTime modified; // UTC
  final int size;

  const WebdavFile({
    required this.name,
    required this.modified,
    required this.size,
  });

  bool get isEncrypted => name.toLowerCase().endsWith('.suiya');

  String get sizeText {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// WebDAV 业务异常（message 直接面向用户展示）
class WebdavException implements Exception {
  final String message;
  WebdavException(this.message);
  @override
  String toString() => message;
}

class WebdavClient {
  final WebdavConfig config;
  final String password;

  WebdavClient({required this.config, required this.password});

  HttpClient? _client;

  HttpClient get _http {
    final c = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    // 自签证书场景的显式开关，默认严格校验
    if (config.ignoreCert) {
      c.badCertificateCallback = (cert, host, port) => true;
    }
    return c;
  }

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('${config.username}:$password'))}';

  void close() {
    _client?.close();
    _client = null;
  }

  // ---------- 5 个 WebDAV 方法 ----------

  /// 列出 [dir] 下的文件（不含子目录），按修改时间倒序
  Future<List<WebdavFile>> propFind(String dir) async {
    final uri = buildDavUri(serverUrl: config.serverUrl, dir: dir);
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/><d:getcontentlength/><d:getlastmodified/>'
        '<d:resourcetype/></d:prop></d:propfind>';
    final res = await _send('PROPFIND', uri,
        headers: {'Depth': '1', 'Content-Type': 'application/xml'},
        body: utf8.encode(body));
    if (res.statusCode == 404) return const [];
    final text = await utf8.decodeStream(res);
    _checkStatus(res.statusCode, context: '读取云端列表');
    return _parseMultistatus(text);
  }

  /// 逐级创建目录；405（已存在）视为成功
  Future<void> mkcolRecursive(String dir) async {
    final segments = normalizeDir(dir).split('/').where((s) => s.isNotEmpty);
    var current = '';
    for (final seg in segments) {
      current = '$current/$seg';
      final uri = buildDavUri(
          serverUrl: config.serverUrl, dir: current);
      final res = await _send('MKCOL', uri);
      final code = res.statusCode;
      // 405 = 目录已存在；201 = 创建成功；其他视为错误
      if (code != 201 && code != 405) {
        _checkStatus(code, context: '创建云端目录');
      }
    }
  }

  /// 上传文件（字节数组；导出本身就是内存字节，量级几十 MB 可接受）
  Future<void> putBytes(String dir, String fileName, Uint8List bytes) async {
    final uri = buildDavUri(
        serverUrl: config.serverUrl, dir: dir, fileName: fileName);
    final res = await _send('PUT', uri, body: bytes);
    _checkStatus(res.statusCode, context: '上传备份');
  }

  /// 下载文件
  Future<Uint8List> getFile(String dir, String fileName) async {
    final uri = buildDavUri(
        serverUrl: config.serverUrl, dir: dir, fileName: fileName);
    final res = await _send('GET', uri);
    _checkStatus(res.statusCode, context: '下载备份');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  /// 删除文件（多版本清理用；404 视为已不存在）
  Future<void> delete(String dir, String fileName) async {
    final uri = buildDavUri(
        serverUrl: config.serverUrl, dir: dir, fileName: fileName);
    final res = await _send('DELETE', uri);
    if (res.statusCode == 404) return;
    _checkStatus(res.statusCode, context: '清理旧版本');
  }

  // ---------- 内部 ----------

  Future<HttpClientResponse> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    try {
      final req = await _http.openUrl(method, uri);
      req.headers.set(HttpHeaders.authorizationHeader, _authHeader);
      headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentLength = body.length;
        req.add(body);
      }
      // 上传/下载几十 MB 的备份，单请求超时放宽到 120s
      return await req.close().timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw WebdavException('连接超时，请检查网络与服务器地址');
    } on SocketException catch (e) {
      throw WebdavException('无法连接服务器：${e.message}');
    } on HandshakeException {
      throw WebdavException('TLS 握手失败。自签证书可在配置里开启「忽略证书校验」');
    } on HttpException catch (e) {
      throw WebdavException('请求失败：${e.message}');
    }
  }

  void _checkStatus(int code, {required String context}) {
    if (code >= 200 && code < 300) return;
    if (code == 401 || code == 403) {
      throw WebdavException('账号或密码错误（坚果云需使用「应用密码」）');
    }
    if (code == 404) {
      throw WebdavException('$context：云端文件不存在（404）');
    }
    if (code == 507) {
      throw WebdavException('云端空间不足（507）');
    }
    throw WebdavException('$context失败（HTTP $code）');
  }

  /// 解析 PROPFIND 的 multistatus XML
  ///
  /// 用 local name 匹配元素：不同厂商的命名空间前缀（d:/D:/lp1: 等）不统一。
  List<WebdavFile> _parseMultistatus(String xmlText) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlText);
    } catch (e) {
      throw WebdavException('云端返回了无法解析的数据');
    }
    final files = <WebdavFile>[];
    for (final response in doc.descendantElements) {
      if (response.name.local != 'response') continue;
      // resourcetype 里有 collection 的条目是目录，跳过
      final isCollection = response.descendantElements
          .any((e) => e.name.local == 'collection');
      if (isCollection) continue;

      String? href;
      int size = 0;
      DateTime modified = DateTime.now().toUtc();
      for (final el in response.descendantElements) {
        switch (el.name.local) {
          case 'href':
            href ??= el.innerText;
          case 'getcontentlength':
            size = int.tryParse(el.innerText.trim()) ?? 0;
          case 'getlastmodified':
            final parsed = _parseHttpDate(el.innerText.trim());
            if (parsed != null) modified = parsed;
        }
      }
      // displayname 兜底：部分服务器 href 为空
      String? displayName;
      for (final el in response.descendantElements) {
        if (el.name.local == 'displayname') {
          displayName = el.innerText;
          break;
        }
      }
      var name = displayName?.trim() ?? '';
      if (name.isEmpty && href != null && href.isNotEmpty) {
        final decoded = Uri.tryParse(href)?.path ?? href;
        final parts = decoded.split('/').where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) name = Uri.decodeComponent(parts.last);
      }
      if (name.isEmpty) continue;
      files.add(WebdavFile(name: name, modified: modified, size: size));
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  /// 解析 HTTP 日期（RFC 1123，如 "Mon, 02 Jan 2026 03:04:05 GMT"）
  DateTime? _parseHttpDate(String raw) {
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return null;
    }
  }
}
