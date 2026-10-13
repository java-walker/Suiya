import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('X1 纯 Flutter 最小渲染', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('hi'))));
    await tester.pump();
    // ignore: avoid_print
    print('>>> X1 ok, found=${find.text('hi').evaluate().length}');
    expect(find.text('hi'), findsOneWidget);
  });
}
