import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    // MARK: - Application Lifecycle
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Configure Flutter engine
        GeneratedPluginRegistrant.register(with: self)
        
        // ==================== Amr AI - Security Configuration ====================
        
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
    
    // MARK: - Screen Protection
    private func setupScreenProtection() {
        // This will be handled by screen_protector plugin
        // Additional native implementation for extra security
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCaptureDetected),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func screenCaptureDetected() {
        if UIScreen.main.isCaptured {
            // Screen recording detected - handled by plugin
            print("⚠️ Amr AI Security: Screen recording detected")
        }
    }
    
    // MARK: - Audio Protection
    private func setupAudioProtection() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
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
    }
    
    private func unblurScreen() {
        guard let window = UIApplication.shared.windows.first else { return }
        window.viewWithTag(9999)?.removeFromSuperview()
        self.blurView = nil
    }
    
    // MARK: - Prevent Mirroring
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        
        // Check for mirroring
        if UIScreen.screens.count > 1 {
            print("⚠️ Amr AI Security: External display detected")
            // This will be handled by the Flutter plugin
        }
    }
}
