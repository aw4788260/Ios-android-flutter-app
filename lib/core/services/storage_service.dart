import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  // التخزين الآمن للمفاتيح فقط
  static const _secureStorage = FlutterSecureStorage();
  static List<int>? _encryptionKey;

  /// دالة داخلية: توليد أو استرجاع مفتاح التشفير من المنطقة الآمنة للهاتف
  static Future<List<int>> _getKey() async {
    // 1. إذا كان المفتاح موجوداً في الذاكرة، استخدمه فوراً
    if (_encryptionKey != null) return _encryptionKey!;

    // 2. محاولة قراءة المفتاح من التخزين الآمن (Keystore/Keychain)
    String? keyString = await _secureStorage.read(key: 'hive_key');
    
    if (keyString == null) {
      // 3. إذا لم يوجد (أول مرة)، قم بتوليد مفتاح عشوائي جديد وحفظه
      final key = Hive.generateSecureKey();
      // ✅ تصحيح: استخدام base64Url.encode
      await _secureStorage.write(key: 'hive_key', value: base64Url.encode(key));
      _encryptionKey = key;
    } else {
      // 4. إذا وجد، قم بفك تشفيره لاستخدامه
      // ✅ تصحيح: استخدام base64Url.decode
      _encryptionKey = base64Url.decode(keyString);
    }
    return _encryptionKey!;
  }

  /// ✅ الدالة الرئيسية: فتح أي صندوق بنظام التشفير
  static Future<Box> openBox(String boxName) async {
    try {
      final key = await _getKey();
      return await Hive.openBox(
        boxName,
        encryptionCipher: HiveAesCipher(key), // تفعيل التشفير هنا
      );
    } catch (e) {
      // في حالة تلف البيانات أو تغيير المفتاح، نعيد إنشاء الصندوق لتجنب توقف التطبيق
      print("Error opening encrypted box $boxName: $e");
      await Hive.deleteBoxFromDisk(boxName);
      final key = await _getKey();
      return await Hive.openBox(
        boxName,
        encryptionCipher: HiveAesCipher(key),
      );
    }
  }

  // ==========================================================
  // 🆕 دوال جديدة لحفظ البيانات بشكل دائم (تستخدم للأوفلاين)
  // ==========================================================

  // 1. حفظ واسترجاع رقم الهاتف (للعلامة المائية)
  static Future<void> saveUserPhone(String phone) async {
    final box = await openBox('auth_box');
    await box.put('user_phone_watermark', phone);
  }

  static Future<String?> getUserPhone() async {
    final box = await openBox('auth_box');
    return box.get('user_phone_watermark');
  }

  // 2. حفظ واسترجاع معلومات التواصل (واتساب / تليجرام)
  static Future<void> saveContactInfo({required String whatsapp, required String telegram}) async {
    final box = await openBox('settings_box');
    await box.put('contact_whatsapp', whatsapp);
    await box.put('contact_telegram', telegram);
  }

  static Future<Map<String, String?>> getContactInfo() async {
    final box = await openBox('settings_box');
    return {
      'whatsapp': box.get('contact_whatsapp'),
      'telegram': box.get('contact_telegram'),
    };
  }
}
