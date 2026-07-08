import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usb_camera_monitor/main.dart';
import 'package:usb_camera_monitor/services/locale_service.dart';

void main() {
  testWidgets('app widget builds without throwing', (WidgetTester tester) async {
    final localeService = LocaleService();
    await localeService.load();
    await tester.pumpWidget(USBCameraApp(localeService: localeService));
    // 触发首帧及异步摄像头扫描（不等待动画，避免超时）
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
