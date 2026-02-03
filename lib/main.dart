import 'dart:async';
import 'dart:io';
import 'package:Medaad/firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:safe_device/safe_device.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';
import 'core/services/app_state.dart';
// ✅ استيراد خدمة الحماية الخاصة التي أثبتت نجاحها
import 'core/services/audio_protection_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    await NotificationService().init();
    // await initializeService();

    // Hive
    await Hive.initFlutter();
    await Hive.openBox('auth_box');
    await Hive.openBox('settings_box');
    await Hive.openBox('downloads_box');
    await Hive.openBox('pdf_drawings_db');

    MediaKit.ensureInitialized();

    // ✅ إعداد جلسة الصوت
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.movie,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    await _enableSecureMode();

    // Security
    SecurityManager.instance.initListeners();
    // Start periodic check
    SecurityManager.instance.startPeriodicCheck();

    // Theme
    await AppState().initTheme();

    runApp(
      const RestartWidget(
        child: EduVantageApp(),
      ),
    );
  }, (error, stack) async {
    if (Firebase.apps.isNotEmpty) {
      await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

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

  // فحص الأمان للروت وخيارات المطور
  Future<bool> checkSecurity() async {
    // إذا كان هناك سبب مسجل بالفعل، نعتبر الجهاز مخترقاً ولا نعيد الفحص
    if (securityBreachReason.value != null) return false;

    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;

      // ✅ تحديد السبب بدقة
      if (isJailBroken) {
        _triggerBreach("الجهاز مكسور الحماية (Root)");
        return false;
      }

      if (isDevMode) {
        _triggerBreach("خيارات المطور مفعلة (Developer Options)");
        return false;
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
    return true;
  }

  // Start periodic check for jailbreak/dev mode
  void startPeriodicCheck() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      await checkSecurity();
    });
  }

  // ✅ دالة تفعيل الإنذار تستقبل السبب وتخزنه للعرض
  void _triggerBreach(String reason) {
    if (securityBreachReason.value != null) return;

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
}

// Future<void> initializeService() async {
// final service = FlutterBackgroundService();

//   await service.configure(
//     androidConfiguration: AndroidConfiguration(
//       onStart: onStart,
//       autoStart: false,
//       isForegroundMode: true,
//       notificationChannelId: 'downloads_channel',
//       initialNotificationTitle: 'مــــداد',
//       initialNotificationContent: 'Initializing downloads...',
//       foregroundServiceNotificationId: 888,
//     ),
//     iosConfiguration: IosConfiguration(
//       autoStart: false,
//       onForeground: onStart,
//       onBackground: onIosBackground,
//     ),
//   );
// }

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  Timer? watchdogTimer;

  void resetWatchdog() {
    watchdogTimer?.cancel();
    watchdogTimer = Timer(const Duration(seconds: 10), () {
      service.stopSelf();
    });
  }

  resetWatchdog();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('keepAlive').listen((event) {
    resetWatchdog();
  });
}

@pragma('vm:entry-point')
bool onIosBackground(ServiceInstance service) {
  return true;
}

Future<void> _enableSecureMode() async {
  try {
    await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE);
  } catch (e) {
    debugPrint("Security Mode Error: $e");
  }
}

class EduVantageApp extends StatefulWidget {
  const EduVantageApp({super.key});

  @override
  State<EduVantageApp> createState() => _EduVantageAppState();
}

class _EduVantageAppState extends State<EduVantageApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة تفعيل الحظر عند العودة للتطبيق
      AudioProtectionService().blockAudioCapture();
      SecurityManager.instance.checkSecurity();
    }
  }

  @override
  Widget build(BuildContext context) {
    const MethodChannel _settingsChannel = MethodChannel("app.settings");
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState().themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'مــــداد',
          theme: AppTheme.darkTheme.copyWith(
            brightness: currentMode == ThemeMode.dark
                ? Brightness.dark
                : Brightness.light,
          ),
          themeMode: currentMode,

          // ✅ هنا نطبق "الشاشة الحمراء" كطبقة فوق كل التطبيق (Global Overlay)
          builder: (context, child) {
            return Stack(
              textDirection: TextDirection.ltr,
              children: [
                if (child != null) child, // التطبيق الطبيعي

                // ✅ التعديل: الاستماع لمتغير النص (String?) بدلاً من البوليان
                //???????!/
                ValueListenableBuilder<String?>(
                  valueListenable:
                      SecurityManager.instance.securityBreachReason,
                  builder: (context, breachReason, _) {
                    // إذا كان السبب null (لا يوجد اختراق)، نخفي الطبقة
                    if (breachReason == null) return const SizedBox.shrink();

                    // 🛑 إذا وجد نص، نظهر الشاشة الحمراء مع السبب المحدد
                    return Material(
                      type: MaterialType.transparency,
                      child: Container(
                        color: Colors.red.shade900, // لون أحمر داكن للتحذير
                        width: double.infinity,
                        height: double.infinity,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.shieldAlert,
                                color: Colors.white, size: 80),
                            const SizedBox(height: 24),
                            const Text(
                              "SECURITY ALERT",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // ✅ عرض سبب المشكلة الفعلي القادم من SecurityManager
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                breachReason, // هنا سيظهر النص المحدد (مثلاً: خيارات المطور مفعلة)
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // ⚠️ صندوق التهديد بالحظر
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.yellow, width: 2),
                              ),
                              child: const Column(
                                children: [
                                  Text(
                                    "⚠️ تنويه",
                                    style: TextStyle(
                                        color: Colors.yellow,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.none),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "يرجى إغلاق التطبيقات المخالفة أو إيقاف خيارات المطور لضمان عمل التطبيق بأمان.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        decoration: TextDecoration.none),
                                    textDirection: TextDirection.rtl,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 40),
                            // ElevatedButton(
                            //   onPressed: () => exit(0), // إغلاق التطبيق فوراً
                            //   style: ElevatedButton.styleFrom(
                            //     backgroundColor: Colors.white,
                            //     foregroundColor: Colors.red.shade900,
                            //     padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            //   ),
                            //   child: const Text("إغلاق التطبيق / EXIT", style: TextStyle(fontWeight: FontWeight.bold)),
                            // )
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    // إعادة المحاولة بعد أن المستخدم يصلح المشكلة
                                    SecurityManager.instance
                                        .securityBreachReason.value = null;
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.red.shade900,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: const Text(
                                    "إعادة المحاولة",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // زر اختياري لفتح الإعدادات
                                ElevatedButton(
                                  onPressed: () async {
                                    try {
                                      await _settingsChannel
                                          .invokeMethod("openSettings");
                                    } catch (e) {
                                      debugPrint("Failed to open settings: $e");
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: const Text(
                                    "فتح الإعدادات",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}

// =========================================================
// 🔄 كلاس إعادة تشغيل التطبيق (RestartWidget)
// =========================================================
class RestartWidget extends StatefulWidget {
  final Widget child;
  const RestartWidget({super.key, required this.child});

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  _RestartWidgetState createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
}
