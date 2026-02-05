package medaad.app

import android.os.Bundle
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import android.os.Handler
import android.os.Looper

class MainActivity: FlutterActivity() {
    // اسم القناة للتواصل مع كود Flutter
    private val CHANNEL = "com.example.edu_vantage_app/audio_protection"
    
    private var audioManager: AudioManager? = null
    private var handler: Handler? = null
    private var recordingCheckRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 🛑 تم الايقاف: منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE)
        // window.setFlags(
        //     WindowManager.LayoutParams.FLAG_SECURE,
        //     WindowManager.LayoutParams.FLAG_SECURE
        // )

        // 🛑 تم الايقاف: منع تسجيل الصوت الداخلي
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                // audioManager?.allowedCapturePolicy = 3 // تم التعليق
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 🛑 تم الايقاف: بدء حلقة المراقبة المستمرة للتطبيقات الخارجية
        // startRecordingMonitoring()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRecording" -> {
                    // 🛑 تعديل: دائماً نرجع false (لا يوجد تسجيل)
                    result.success(false) 
                }
                "getAudioMode" -> {
                    val mode = audioManager?.mode ?: -1
                    result.success(mode)
                }
                "blockAudioCapture" -> {
                    // 🛑 تعديل: نرجع true وكأننا نفذنا الأمر بنجاح ولكن بدون تنفيذ فعلي
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ✅ دالة فحص التسجيل النشط
    private fun checkIfRecording(): Boolean {
        // 🛑 تعديل: تم إيقاف الفحص وإرجاع false دائماً
        return false;
        
        /* // الكود القديم (تم تعليقه)
        try {
            if (audioManager == null) {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            }
            
            val audioMode = audioManager?.mode
            if (audioMode == AudioManager.MODE_IN_COMMUNICATION || 
                audioMode == AudioManager.MODE_IN_CALL) {
                return true
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val activeRecordings = audioManager?.activeRecordingConfigurations
                if (!activeRecordings.isNullOrEmpty()) {
                    return true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
        */
    }

    // ✅ تشغيل مراقبة مستمرة في الخلفية كل 2 ثانية
    private fun startRecordingMonitoring() {
        // 🛑 الدالة موجودة ولكن لن يتم استدعاؤها لأننا علقنا الاستدعاء في onCreate
        handler = Handler(Looper.getMainLooper())
        recordingCheckRunnable = object : Runnable {
            override fun run() {
                if (checkIfRecording()) {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("onRecordingDetected", true)
                    }
                }
                handler?.postDelayed(this, 2000)
            }
        }
        handler?.post(recordingCheckRunnable!!)
    }

    override fun onResume() {
        super.onResume()
        // 🛑 تم الايقاف: إعادة تطبيق حظر الصوت عند العودة للتطبيق
        // if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        //     audioManager?.allowedCapturePolicy = 3
        // }
    }

    override fun onDestroy() {
        if (handler != null && recordingCheckRunnable != null) {
            handler?.removeCallbacks(recordingCheckRunnable!!)
        }

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
        }
        
        super.onDestroy()
    }
}
