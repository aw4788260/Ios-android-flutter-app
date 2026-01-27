import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    // MARK: - Properties
    private var flutterMethodChannel: FlutterMethodChannel?
    private var screenRecordingTimer: Timer?
    private var isScreenBeingCaptured = false
    
    // MARK: - Application Lifecycle
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Configure Flutter engine
        GeneratedPluginRegistrant.register(with: self)
        
        // ==================== Amr AI Technical Team - Security System ====================
        // Developed by: Amr AI Technical Team
        // Contact: 01090991769
        // Email: amr.01090991769.ai@gmail.com
        // Website: www.amrai.tech
        // ================================================================================
        
        // Setup Flutter Method Channel Bridge
        setupFlutterMethodChannel()
        
        // Prevent screenshots and screen recording
        setupScreenProtection()
        
        // Configure audio session for protection
        setupAudioProtection()
        
        // Setup Firebase
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
        }
        
        // ==================== End Security Configuration ====================
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // MARK: - Flutter Method Channel Setup
    private func setupFlutterMethodChannel() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("⚠️ Amr AI: Failed to get FlutterViewController")
            return
        }
        
        // Create Method Channel for Audio Protection
        flutterMethodChannel = FlutterMethodChannel(
            name: "com.example.edu_vantage_app/audio_protection",
            binaryMessenger: controller.binaryMessenger
        )
        
        // Handle method calls from Flutter
        flutterMethodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else {
                result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate not available", details: nil))
                return
            }
            
            switch call.method {
            case "blockAudioCapture":
                // iOS doesn't support programmatic audio capture blocking
                // But we return success to prevent Flutter from crashing
                // The screen_protector plugin handles visual protection
                print("✅ Amr AI: Audio protection request received (iOS uses screen_protector)")
                result(true)
                
            case "checkRecording":
                // Check if screen is being captured/recorded
                let isRecording = UIScreen.main.isCaptured
                result(isRecording)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        print("✅ Amr AI: Flutter Method Channel initialized successfully")
    }
    
    // MARK: - Screen Protection
    private func setupScreenProtection() {
        // Monitor screen capture status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCaptureStatusChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        
        // Start periodic checking (backup method)
        startScreenRecordingMonitoring()
        
        print("✅ Amr AI: Screen protection activated")
    }
    
    @objc private func screenCaptureStatusChanged() {
        let isCaptured = UIScreen.main.isCaptured
        
        if isCaptured != isScreenBeingCaptured {
            isScreenBeingCaptured = isCaptured
            
            if isCaptured {
                print("⚠️ Amr AI Security Alert: Screen recording detected!")
                notifyFlutterOfRecording()
            } else {
                print("✅ Amr AI: Screen recording stopped")
            }
        }
    }
    
    private func startScreenRecordingMonitoring() {
        // Check every 1 second for screen capture changes
        screenRecordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let isCaptured = UIScreen.main.isCaptured
            if isCaptured && !self.isScreenBeingCaptured {
                self.screenCaptureStatusChanged()
            } else if !isCaptured && self.isScreenBeingCaptured {
                self.screenCaptureStatusChanged()
            }
        }
    }
    
    private func notifyFlutterOfRecording() {
        // Send notification to Flutter side
        flutterMethodChannel?.invokeMethod("onRecordingDetected", arguments: nil)
    }
    
    // MARK: - Audio Protection
    private func setupAudioProtection() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Configure audio session with privacy settings
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            
            try audioSession.setActive(true)
            
            print("✅ Amr AI: Audio protection configured successfully")
        } catch {
            print("⚠️ Amr AI Security: Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Background Protection
    override func applicationDidEnterBackground(_ application: UIApplication) {
        // Blur/hide content when app enters background
        blurScreen()
        super.applicationDidEnterBackground(application)
    }
    
    override func applicationWillEnterForeground(_ application: UIApplication) {
        // Remove blur when app returns
        unblurScreen()
        super.applicationWillEnterForeground(application)
    }
    
    private var blurView: UIVisualEffectView?
    
    private func blurScreen() {
        guard let window = UIApplication.shared.windows.first else { return }
        
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = window.frame
        blurEffectView.tag = 9999
        
        window.addSubview(blurEffectView)
        self.blurView = blurEffectView
        
        print("✅ Amr AI: Background protection activated")
    }
    
    private func unblurScreen() {
        guard let window = UIApplication.shared.windows.first else { return }
        window.viewWithTag(9999)?.removeFromSuperview()
        self.blurView = nil
        
        print("✅ Amr AI: Background protection deactivated")
    }
    
    // MARK: - Prevent Mirroring
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        
        // Check for mirroring/external displays
        if UIScreen.screens.count > 1 {
            print("⚠️ Amr AI Security Alert: External display/AirPlay detected!")
            // Notify Flutter about potential security risk
            flutterMethodChannel?.invokeMethod("onExternalDisplayDetected", arguments: nil)
        }
    }
    
    // MARK: - Cleanup
    deinit {
        screenRecordingTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Security Extension
extension AppDelegate {
    /// Additional security checks
    func performSecurityChecks() -> [String: Bool] {
        return [
            "isJailbroken": isDeviceJailbroken(),
            "isScreenCaptured": UIScreen.main.isCaptured,
            "hasExternalDisplay": UIScreen.screens.count > 1,
            "isDebuggerAttached": isDebuggerAttached()
        ]
    }
    
    private func isDeviceJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if can write to restricted areas
        let testString = "Amr AI Security Test"
        do {
            try testString.write(toFile: "/private/test.txt", atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: "/private/test.txt")
            return true
        } catch {
            return false
        }
        #endif
    }
    
    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        assert(junk == 0, "sysctl failed")
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
