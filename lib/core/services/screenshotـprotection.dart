import 'package:flutter/services.dart';

class ScreenshotProtection {
  static const _channel = MethodChannel('screenshot_protection');

  // تفعيل الحماية
  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('enableProtection');
      print('✅ Screenshot protection enabled');
    } catch (e) {
      print('❌ Error enabling protection: $e');
    }
  }

  // تعطيل الحماية
  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disableProtection');
      print('✅ Screenshot protection disabled');
    } catch (e) {
      print('❌ Error disabling protection: $e');
    }
  }
}
