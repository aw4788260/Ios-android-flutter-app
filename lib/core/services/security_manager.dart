import 'dart:async';

import 'package:Medaad/core/services/audio_protection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_device/safe_device.dart';
import 'package:screen_protector/screen_protector.dart';

// =========================================================
// 🛡️ كلاس إدارة الحماية (Security Manager) - النسخة المحدثة
// =========================================================

class SecurityManager {
  static final SecurityManager instance = SecurityManager._internal();
  SecurityManager._internal();

  // ✅ التعديل: استبدال المتغير البولياني بمتغير نصي يحمل سبب الحظر
  // إذا كان null فهذا يعني أن الوضع آمن. إذا كان يحتوي على نص فهذا هو سبب الحظر.
  final ValueNotifier<String?> securityBreachReason = ValueNotifier(null);

  // ✅ الاعتماد على خدمة الحماية الخاصة التي نجحت في المشغل
  final AudioProtectionService _audioProtection = AudioProtectionService();

  void initListeners() {
    // 1. تشغيل المراقبة من خدمتك الخاصة (AudioProtectionService)
    _audioProtection.startMonitoring();

    // 2. الاستماع للـ Stream القادم من خدمتك
    _audioProtection.recordingStateStream.listen((isRecording) {
      if (isRecording) {
        _triggerBreach("تم اكتشاف تسجيل للشاشة أو الصوت!");
      }
    });

    // 3. (إضافي) الاستماع لمكتبة ScreenProtector كطبقة حماية ثانية
    ScreenProtector.addListener(() {
      // Screenshot callback
    }, (isCapturing) {
      if (isCapturing) _triggerBreach("تم اكتشاف تصوير للشاشة!");
    });
  }

  // فحص الأمان للروت، خيارات المطور، والمحاكي
  Future<bool> checkSecurity() async {
    // إذا كان هناك سبب مسجل بالفعل، نعتبر الجهاز مخترقاً ولا نعيد الفحص
    if (securityBreachReason.value != null) return false;

    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
      bool isRealDevice = await SafeDevice.isRealDevice; // ✅ إضافة فحص المحاكي

      // ✅ منع المحاكي (Emulator) نهائياً
      if (!isRealDevice) {
        _triggerBreach("غير مسموح بتشغيل التطبيق على المحاكي (Emulator)");
        return false;
      }

      // ✅ منع الروت أو الجيلبريك نهائياً
      if (isJailBroken) {
        _triggerBreach("عفواً، الجهاز مكسور الحماية (Root / Jailbreak)");
        return false;
      }

      // ✅ منع خيارات المطور
      if (isDevMode) {
        _triggerBreach("خيارات المطور مفعلة (Developer Options)");
        return false;
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
    return true;
  }

  // Start periodic check for jailbreak/dev mode/emulator
  void startPeriodicCheck() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      await checkSecurity();
    });
  }

  // ✅ دالة تفعيل الإنذار تستقبل السبب وتخزنه للعرض
  void _triggerBreach(String reason) {
    // if (securityBreachReason.value != null) return;

    debugPrint("🚨 SECURITY BREACH: $reason");

    // تأكد أن التحديث يتم على الـ UI Thread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      securityBreachReason.value = reason;
    });

    // أوقف الصوت فورًا
    _audioProtection.blockAudioCapture();

    // (اختياري) اهتزاز تحذيري
    HapticFeedback.heavyImpact();
  }

  Future<bool> forceReCheck() async {
    // إعادة فحص حقيقية من الـ Native لكل الأسباب
    bool isRecording = await _audioProtection.checkRecordingStatus(); // تأكد أن هذه تنادي الـ MethodChannel
    bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
    bool isJailBroken = await SafeDevice.isJailBroken;
    bool isRealDevice = await SafeDevice.isRealDevice; // ✅ فحص المحاكي

    // ✅ تفعيل جميع الشروط معاً للتأكد من الأمان الكامل قبل إخفاء الشاشة الحمراء
    if (!isRecording && !isDevMode && !isJailBroken && isRealDevice) {
      securityBreachReason.value = null; // سيؤدي لإخفاء الشاشة الحمراء
      return true;
    } else {
      // تحديث السبب سيجعل الواجهة "تنفض" نفسها وتظهر النص الجديد
      if (isRecording) {
        securityBreachReason.value = "لا يزال تسجيل الشاشة قيد العمل!";
      } else if (!isRealDevice) {
        securityBreachReason.value = "لا يمكنك استخدام المحاكي، استخدم هاتف حقيقي!";
      } else if (isDevMode) {
        securityBreachReason.value = "خيارات المطور لا تزال مفعلة!";
      } else if (isJailBroken) {
        securityBreachReason.value = "الجهاز لا يزال مكسور الحماية!";
      } else {
        securityBreachReason.value = "تم اكتشاف خرق أمني!";
      }
      return false;
    }
  }
}
