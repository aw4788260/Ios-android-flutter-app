import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ✅ مكتبات الحماية
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/services/audio_protection_service.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';

class YoutubePlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;

  const YoutubePlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
  });

  @override
  State<YoutubePlayerScreen> createState() => _YoutubePlayerScreenState();
}

// ✅ إضافة Mixin لمراقبة حالة التطبيق
class _YoutubePlayerScreenState extends State<YoutubePlayerScreen> with WidgetsBindingObserver {
  late YoutubePlayerController _controller;
  
  // ✅ متغيرات الحماية
  final AudioProtectionService _protectionService = AudioProtectionService();
  StreamSubscription? _recordingSubscription;
  bool _isRecordingDetected = false;
    
  // متغيرات العلامة المائية
  Timer? _watermarkTimer;
  Alignment _watermarkAlignment = Alignment.topRight;
  String _userIdText = ""; 

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ✅ تفعيل المراقب
    
    // ✅ 1. تفعيل وضع ملء الشاشة الأفقي
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // ✅ 2. تفعيل Wakelock لمنع انطفاء الشاشة
    WakelockPlus.enable();

    // ✅ 3. تفعيل الحماية الأمنية
    // 🛑 تم الايقاف: عدم تفعيل الحماية عند البدء
    // _initializeProtection();

    // ✅ 4. جلب رقم الهاتف وبدء التحريك
    _getUserId();
    _startWatermarkAnimation();

    // ✅ 5. إعداد المشغل
    try {
      _controller = YoutubePlayerController(
        initialVideoId: widget.videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          hideControls: false,
          forceHD: false,
          isLive: false,
          loop: false,
          enableCaption: false, 
          disableDragSeek: false, 
        ),
      )..addListener(_playerListener);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Youtube Player Init Error');
    }
  }

  // ✅ دالة تفعيل الحماية
  Future<void> _initializeProtection() async {
    // 🛑 تم الايقاف بالكامل
    /*
    try {
      // منع Screenshot & Screen Recording
      // ✅ تم التصحيح هنا: استخدام FlutterWindowManagerPlus بدلاً من FlutterWindowManager
      await FlutterWindowManagerPlus.addFlags(FlutterWindowManagerPlus.FLAG_SECURE);
      
      // حظر التقاط الصوت
      await _protectionService.blockAudioCapture();
      
      // بدء مراقبة تطبيقات التسجيل
      await _protectionService.startMonitoring();
      
      // الاستماع لأي محاولة تسجيل
      _recordingSubscription = _protectionService.recordingStateStream.listen((isRecording) {
        if (isRecording) {
          _handleRecordingDetected();
        }
      });
    } catch (e) {
      FirebaseCrashlytics.instance.recordError(e, null, reason: 'Protection Init Error');
    }
    */
  }

  // ✅ التعامل مع اكتشاف التسجيل (تم التعديل لإيقاف الصوت)
  void _handleRecordingDetected() {
    // 🛑 تم الايقاف: لن يتم تنفيذ أي حظر
    return;

    /*
    if (!mounted) return;
    
    // حتى إذا تم الكشف مسبقاً، نتأكد من تطبيق الإيقاف مرة أخرى
    setState(() => _isRecordingDetected = true);
    
    // 🛑 كتم الصوت وإيقاف الفيديو فوراً
    _controller.mute(); // كتم الصوت
    _controller.pause(); // إيقاف الفيديو
    
    FirebaseCrashlytics.instance.log("🚨 Security: Screen Recording Detected on YouTube Player! Muted & Paused.");
    */
  }

  // ✅ إعادة تفعيل الحماية عند العودة للتطبيق
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      // 🛑 تم الايقاف: عدم إعادة تفعيل الحظر
      // _protectionService.blockAudioCapture();
      
      // إذا كان هناك تسجيل، نعيد تطبيق الحظر (كتم وإيقاف)
      if (_isRecordingDetected) {
         // لن يتم الدخول هنا أبداً لأن _isRecordingDetected دائماً false
         _controller.mute();
         _controller.pause();
      }
    }
  }

  void _playerListener() {
    if (_controller.value.hasError) {
      FirebaseCrashlytics.instance.log("Youtube Player Error: ${_controller.value.errorCode}");
    }
    
    // ✅ حارس إضافي: إذا كان الفيديو يعمل وهناك تسجيل، أوقفه
    // 🛑 تم الايقاف
    /*
    if (_isRecordingDetected && _controller.value.isPlaying) {
       _controller.pause();
       _controller.mute();
    }
    */
  }

  void _getUserId() {
    String displayText = '';
      
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] ?? '';
    }

    if (displayText.isEmpty) {
      try {
        if (Hive.isBoxOpen('auth_box')) {
          var box = Hive.box('auth_box');
          displayText = box.get('phone') ?? box.get('username') ?? '';
        }
      } catch (e) {
        // ignore
      }
    }

    setState(() {
      _userIdText = displayText.isNotEmpty ? displayText : 'User';
    });
  }

  void _startWatermarkAnimation() {
    _watermarkTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted) {
        setState(() {
          final random = Random();
          double x = (random.nextDouble() * 1.8) - 0.9;
          double y = (random.nextDouble() * 1.6) - 0.8;
          _watermarkAlignment = Alignment(x, y);
        });
      }
    });
  }

  @override
  void deactivate() {
    _controller.pause();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ إزالة المراقب
    _recordingSubscription?.cancel();
    // 🛑 تم الايقاف
    // _protectionService.stopMonitoring();
    WakelockPlus.disable(); // ✅ إيقاف Wakelock
    
    _watermarkTimer?.cancel();
    _controller.removeListener(_playerListener);
    _controller.dispose();
      
    // استعادة وضع النظام الطبيعي
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values); 
      
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // استخدام PopScope لمنع الرجوع في حالة التحذير الأمني إذا أردت، أو تركها للتحكم اليدوي
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. مشغل الفيديو
          Center(
            child: YoutubePlayer(
              controller: _controller,
              showVideoProgressIndicator: true,
              progressIndicatorColor: AppColors.accentYellow,
              progressColors: ProgressBarColors(
                playedColor: AppColors.accentYellow,
                handleColor: AppColors.accentYellow,
              ),
              bottomActions: [
                const CurrentPosition(),
                const SizedBox(width: 10),
                const ProgressBar(isExpanded: true),
                const SizedBox(width: 10),
                const RemainingDuration(),
                const PlaybackSpeedButton(),
              ],
            ),
          ),

          // 2. العلامة المائية المتحركة
          AnimatedAlign(
            duration: const Duration(seconds: 2),
            curve: Curves.easeInOut,
            alignment: _watermarkAlignment,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6), 
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _userIdText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9), 
                    fontWeight: FontWeight.bold,
                    fontSize: 11, 
                  ),
                ),
              ),
            ),
          ),

          // 3. زر الرجوع والعنوان
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. ✅ شاشة التحذير الحمراء عند اكتشاف التسجيل (فوق كل شيء)
          // 🛑 تم الايقاف: لن تظهر أبداً لأن _isRecordingDetected دائماً false
          if (_isRecordingDetected)
            Container(
              color: Colors.red.shade900,
              width: double.infinity,
              height: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, color: Colors.white, size: 80),
                  const SizedBox(height: 24),
                  const Text(
                    "SECURITY ALERT",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Screen Recording Detected.\nPlayback has been disabled.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // الخروج من الشاشة
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    ),
                    child: const Text("CLOSE PLAYER", style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
