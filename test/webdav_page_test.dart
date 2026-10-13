// 岁忆 · WebDAV 页 Widget 冒烟测试
//
// 验证页面在真实 provider 图下可渲染（配置读取、表单初始值、
// 厂商预设切换），不发起任何网络请求。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:suiya/core/storage.dart';
import 'package:suiya/features/record/presentation/record_providers.dart';
import 'package:suiya/features/webdav/presentation/webdav_page.dart';

void main() {
  testWidgets('WebDAV 页渲染与预设切换', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SuiyaStorage.open();
    await storage.setRaw(
        'suiya.webdav.v1',
        '{"preset":"jianguoyun","serverUrl":"https://dav.jianguoyun.com/dav/",'
        '"username":"me@example.com","remoteDir":"/suiya/",'
        '"fileNameTemplate":"{date}-backup.suiya","keepCount":5,'
        '"encryptEnabled":true,"ignoreCert":false}');

    await tester.pumpWidget(ProviderScope(
      overrides: [storageProvider.overrideWithValue(storage)],
      child: const MaterialApp(home: WebdavPage()),
    ));
    // 放大测试视口：默认 800x600 下 ListView 懒加载，表单下半部分不会构建
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pump();

    // 配置页关键元素
    expect(find.text('WebDAV 云备份'), findsOneWidget);
    expect(find.text('厂商预设'), findsOneWidget);
    expect(find.text('备份加密'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('备份到云端'), findsOneWidget);
    expect(find.text('从云端恢复'), findsOneWidget);
    // 已保存的配置回填
    TextField serverField() => tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text.startsWith('https://dav.jianguoyun.com') == true));
    expect(serverField().controller!.text, 'https://dav.jianguoyun.com/dav/');
    // 坚果云预设 hint
    expect(serverField().decoration!.hintText, '固定地址，无需修改');
    final userField = tester
        .widget<TextField>(find.widgetWithText(TextField, 'WebDAV 用户名'));
    expect(userField.controller!.text, 'me@example.com');

    // 切换到 Alist 预设：地址内容保留，hint 换成 Alist 的
    await tester.tap(find.text('Alist'));
    await tester.pump();
    expect(serverField().decoration!.hintText, 'http://地址:5244/dav/');
    expect(serverField().controller!.text, 'https://dav.jianguoyun.com/dav/');
  });
}
