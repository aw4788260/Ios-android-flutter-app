import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // 1. تهيئة البلاغن
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // التعامل مع الضغط على الإشعار
      },
    );

    // 2. طلب الأذونات (أندرويد 13+)
    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    await androidImplementation?.requestNotificationsPermission();

    // 3. ✅ إنشاء قنوات الإشعارات يدوياً لتفادي RemoteServiceException
    if (androidImplementation != null) {
      
      // القناة الأولى: للتحميل (صامتة للـ Foreground Service)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'downloads_channel', // نفس الـ ID المستخدم في main.dart و showProgressNotification
          'Active Downloads',
          description: 'Shows progress of active downloads',
          importance: Importance.low, // Low = يظهر بدون صوت (مناسب لشريط التقدم)
          playSound: false,
          showBadge: false,
        ),
      );

      // القناة الثانية: عند اكتمال التحميل (بصوت)
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'download_completed_channel',
          'Download Completed',
          description: 'Notifies when a download finishes',
          importance: Importance.high, // High = يظهر بصوت وتنبيه
          playSound: true,
        ),
      );
    }
  }

  Future<void> cancelNotification(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e, s) {
      FirebaseCrashlytics.instance.recordError(e, s, reason: 'Failed to cancel all notifications');
    }
  }

  Future<void> showProgressNotification({
    required int id,
    required String title,
    required String body,
    required int progress,
    required int maxProgress,
  }) async {
    // استخدام القناة التي أنشأناها بالأعلى
    const String channelId = 'downloads_channel'; 
    
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId, 
      'Active Downloads',
      channelDescription: 'Shows progress of active downloads',
      importance: Importance.low, 
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: progress,
      onlyAlertOnce: true, // تحديث الشريط دون إعادة إصدار صوت/اهتزاز
      ongoing: true, // يمنع المستخدم من حذفه أثناء التحميل
      autoCancel: false,
      playSound: false,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> showCompletionNotification({
    required int id,
    required String title,
    required bool isSuccess,
  }) async {
    const String channelId = 'download_completed_channel';

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      'Download Completed',
      channelDescription: 'Notifies when a download finishes',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      ongoing: false,
      autoCancel: true,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      isSuccess ? 'Download Complete' : 'Download Failed',
      isSuccess ? '$title has been downloaded.' : 'Failed to download $title.',
      platformChannelSpecifics,
    );
  }
}
