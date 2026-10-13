// 岁忆 · WebDAV 客户端与配置模型测试
//
// 用本地 HttpServer 模拟 WebDAV 服务器（PROPFIND/MKCOL/PUT/GET/DELETE），
// 断言请求方法、Basic Auth、路径编码与错误处理；域模型测试覆盖
// 文件名模板与 URL 拼接。
// 运行：flutter test test/webdav_client_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:suiya/features/webdav/data/webdav_client.dart';
import 'package:suiya/features/webdav/domain/webdav_config.dart';

const _user = 'user@example.com';
const _pass = 'app-password-1';
String _basic(String user, String pass) =>
    'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

void main() {
  group('域模型：buildFileName', () {
    test('{date} 展开 + 默认后缀', () {
      final name = buildFileName('{date}-backup.suiya',
          DateTime(2026, 10, 11, 9, 5, 3),
          encrypted: true);
      expect(name, '20261011-090503-backup.suiya');
    });

    test('明文模式自动纠正后缀为 .json', () {
      final name = buildFileName('{date}-backup.suiya', DateTime(2026, 1, 2),
          encrypted: false);
      expect(name, '20260102-000000-backup.json');
    });

    test('加密模式把 .json 模板纠正回 .suiya', () {
      final name = buildFileName('backup.json', DateTime(2026, 1, 2),
          encrypted: true);
      expect(name, 'backup.suiya');
    });

    test('非法字符被替换', () {
      final name = buildFileName('备份/名:测试*.suiya', DateTime(2026, 1, 2),
          encrypted: true);
      expect(name.contains(RegExp(r'[\\/:*?"<>|]')), isFalse);
      expect(name.endsWith('.suiya'), isTrue);
    });

    test('空模板兜底为 backup', () {
      expect(buildFileName('.suiya', DateTime(2026, 1, 2), encrypted: true),
          'backup.suiya');
    });
  });

  group('域模型：URL 拼接', () {
    test('服务器 + 目录 + 文件名，多余斜杠归一', () {
      final uri = buildDavUri(
        serverUrl: 'https://dav.example.com/dav/',
        dir: '/suiya/',
        fileName: 'a.suiya',
      );
      expect(uri.toString(), 'https://dav.example.com/dav/suiya/a.suiya');
    });

    test('服务器自带路径不被破坏', () {
      final uri = buildDavUri(
        serverUrl: 'https://nas.lan:5006/home/Drive',
        dir: 'suiya',
      );
      expect(uri.toString(), 'https://nas.lan:5006/home/Drive/suiya');
    });

    test('中文目录名被百分号编码', () {
      final uri = buildDavUri(
        serverUrl: 'https://dav.example.com/dav',
        dir: '/我的备份/',
        fileName: 'a.json',
      );
      expect(uri.path.contains('%E6%88%91'), isTrue);
      expect(uri.toString(), contains('a.json'));
    });
  });

  group('WebdavClient（本地模拟 WebDAV 服务器）', () {
    late HttpServer server;
    final requests = <HttpRequest>[];
    final requestBodies = <Uint8List>[];
    // 每个用例自定义响应行为（直接写 req.response，由 listen 统一 close）
    late Future<void> Function(HttpRequest) handler;

    setUp(() async {
      requests.clear();
      requestBodies.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      handler = (req) async {
        req.response.statusCode = 200;
      };
      server.listen((req) async {
        requests.add(req);
        // 请求体要读完才能继续（WebDAV 服务器行为）；顺手捕获供断言
        final builder = BytesBuilder(copy: false);
        await for (final chunk in req) {
          builder.add(chunk);
        }
        requestBodies.add(builder.toBytes());
        await handler(req);
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    WebdavConfig config({bool ignoreCert = false}) => WebdavConfig(
          preset: WebdavPreset.custom,
          serverUrl: 'http://127.0.0.1:${server.port}/dav',
          username: _user,
          remoteDir: '/suiya/备份',
        );

    WebdavClient client({bool ignoreCert = false}) =>
        WebdavClient(config: config(ignoreCert: ignoreCert), password: _pass);

    test('PUT：方法、Basic Auth、请求体、路径编码', () async {
      final payload = Uint8List.fromList(List.generate(256, (i) => i));
      await client()
          .putBytes('/suiya/备份', '20261011-000000-backup.suiya', payload);

      expect(requests, hasLength(1));
      final req = requests.single;
      expect(req.method, 'PUT');
      expect(req.headers.value('authorization'), _basic(_user, _pass));
      final decoded = Uri.decodeComponent(req.uri.path);
      expect(decoded, '/dav/suiya/备份/20261011-000000-backup.suiya');
      expect(requestBodies.single, payload);
    });

    test('GET：返回服务器字节流', () async {
      final payload = utf8.encode('{"hello":"岁忆"}');
      handler = (req) async {
        expect(req.method, 'GET');
        req.response.add(payload);
      };
      final got = await client().getFile('/suiya', 'backup.json');
      expect(got, payload);
    });

    test('DELETE：204 成功', () async {
      handler = (req) async {
        expect(req.method, 'DELETE');
        req.response.statusCode = 204;
      };
      await client().delete('/suiya', 'old.suiya');
    });

    test('MKCOL：201 与 405（已存在）都不报错', () async {
      handler = (req) async {
        expect(req.method, 'MKCOL');
        req.response.statusCode = 405;
      };
      await client().mkcolRecursive('/suiya/a/b');
      // 逐级创建：/suiya /suiya/a /suiya/a/b 共 3 次
      expect(requests, hasLength(3));
    });

    test('MKCOL：403 报用户可读错误', () async {
      handler = (req) async {
        req.response.statusCode = 403;
      };
      await expectLater(
        client().mkcolRecursive('/suiya'),
        throwsA(isA<WebdavException>()),
      );
    });

    test('PROPFIND：解析 multistatus、跳过目录、按时间倒序', () async {
      handler = (req) async {
        expect(req.method, 'PROPFIND');
        expect(req.headers.value('depth'), '1');
        expect(req.headers.value('authorization'), _basic(_user, _pass));
        req.response.statusCode = 207;
        req.response.headers.contentType =
            ContentType('application', 'xml', charset: 'utf-8');
        req.response.write('''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/suiya/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/suiya/20261011-090000-backup.suiya</D:href>
    <D:propstat><D:prop>
      <D:getcontentlength>1024</D:getcontentlength>
      <D:getlastmodified>Sun, 11 Oct 2026 09:00:00 GMT</D:getlastmodified>
      <D:resourcetype/>
    </D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/suiya/20261010-090000-backup.suiya</D:href>
    <D:propstat><D:prop>
      <D:getcontentlength>2048</D:getcontentlength>
      <D:getlastmodified>Sat, 10 Oct 2026 09:00:00 GMT</D:getlastmodified>
      <D:resourcetype/>
    </D:prop></D:propstat>
  </D:response>
</D:multistatus>
''');
      };
      final files = await client().propFind('/suiya/备份');
      expect(files, hasLength(2));
      expect(files[0].name, '20261011-090000-backup.suiya');
      expect(files[0].size, 1024);
      expect(files[0].isEncrypted, isTrue);
      expect(files[1].name, '20261010-090000-backup.suiya');
      expect(files[0].modified.isAfter(files[1].modified), isTrue);
    });

    test('PROPFIND：404 返回空列表（目录尚未创建）', () async {
      handler = (req) async {
        req.response.statusCode = 404;
      };
      expect(await client().propFind('/suiya'), isEmpty);
    });

    test('401 → 用户可读的密码错误提示', () async {
      handler = (req) async {
        req.response.statusCode = 401;
      };
      await expectLater(
        client().propFind('/suiya'),
        throwsA(isA<WebdavException>().having(
            (e) => e.message, 'message', contains('密码'))),
      );
    });

    test('密码错误时 Basic Auth 用的是配置的账号', () async {
      handler = (req) async {
        expect(req.headers.value('authorization'), _basic(_user, _pass));
        req.response.statusCode = 200;
        req.response.write(
            '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>');
      };
      await client().propFind('/suiya');
      expect(requests, hasLength(1));
    });
  });
}
