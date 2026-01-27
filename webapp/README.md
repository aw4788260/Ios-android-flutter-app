# 🎓 Medaad - Modern Learning Platform

<div align="center">

![Medaad Logo](assets/images/app_icon.png)

**منصة التعليم الذكية - حماية متقدمة للمحتوى**

[![Flutter](https://img.shields.io/badge/Flutter-3.27-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6-blue.svg)](https://dart.dev)
[![iOS](https://img.shields.io/badge/iOS-13%2B-lightgrey.svg)](https://www.apple.com/ios)
[![Android](https://img.shields.io/badge/Android-5.0%2B-green.svg)](https://www.android.com)

**Developed by Amr AI** | **Contact: 01090991769**

</div>

---

## 📱 Overview

**Medaad** هي منصة تعليمية متطورة توفر تجربة تعلم آمنة ومحمية. التطبيق مصمم خصيصاً لحماية المحتوى التعليمي من التصوير والتسجيل غير المصرح به.

---

## ✨ Key Features

### 🔒 Advanced Security
- ✅ **حماية من التصوير**: منع Screenshot و Screen Recording بالكامل
- ✅ **تشفير AES-256**: جميع الملفات المحملة مشفرة
- ✅ **علامات مائية**: watermarks على جميع الفيديوهات
- ✅ **حماية الصوت**: منع تسجيل الصوت أثناء التشغيل

### 🎥 Video Player
- ✅ جودات متعددة (360p, 720p, 1080p, 4K)
- ✅ علامة مائية ديناميكية
- ✅ تشغيل سلس بدون تقطيع
- ✅ دعم YouTube و Vimeo
- ✅ التحكم الكامل (تقديم، تأخير، سرعة التشغيل)

### 📄 PDF Viewer
- ✅ عرض سريع للملفات الكبيرة
- ✅ أدوات تعليم وهايلايت
- ✅ حفظ الملاحظات
- ✅ تحميل للقراءة بدون إنترنت
- ✅ حماية من النسخ والتصوير

### 💾 Offline Mode
- ✅ تحميل الفيديوهات مع تشفير تلقائي
- ✅ تحميل ملفات PDF
- ✅ حفظ التقدم
- ✅ تشغيل بدون إنترنت

### 📝 Examination System
- ✅ امتحانات تفاعلية
- ✅ أنواع أسئلة متعددة
- ✅ تقييم فوري
- ✅ تتبع الأداء

### 💳 Subscription Management
- ✅ طلب اشتراك سهل
- ✅ رفع إيصالات الدفع
- ✅ تتبع الاشتراكات

---

## 🏗️ Tech Stack

### Frontend
- **Flutter 3.27** - UI Framework
- **Dart 3.6** - Programming Language
- **flutter_bloc** - State Management
- **get_it** - Dependency Injection

### Security
- **screen_protector** - Screenshot Prevention
- **encrypt** - AES Encryption
- **flutter_secure_storage** - Secure Key Storage
- **cryptography** - Advanced Encryption

### Media Players
- **media_kit** - Advanced Video Player
- **pdfrx** - Native PDF Rendering
- **chewie** - Video Player UI
- **youtube_player_flutter** - YouTube Integration

### Storage & Database
- **hive** - Local NoSQL Database
- **shared_preferences** - Settings Storage
- **path_provider** - File System Access

### Networking
- **dio** - HTTP Client
- **connectivity_plus** - Network Status

### Firebase
- **firebase_core** - Firebase SDK
- **firebase_crashlytics** - Crash Reporting

---

## 📁 Project Structure

```
medaad/
├── lib/
│   ├── core/               # Core functionality
│   │   ├── security/       # Security services
│   │   ├── network/        # API clients
│   │   └── utils/          # Utilities
│   ├── features/           # Feature modules
│   │   ├── auth/          # Authentication
│   │   ├── video/         # Video player
│   │   ├── pdf/           # PDF viewer
│   │   ├── offline/       # Offline downloads
│   │   ├── exam/          # Examination system
│   │   └── subscription/  # Subscription management
│   ├── shared/            # Shared widgets
│   └── main.dart          # Entry point
├── android/               # Android configuration
├── ios/                   # iOS configuration
├── assets/                # Images, fonts, etc.
└── test/                  # Unit tests
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.27+
- Dart 3.6+
- Android Studio / Xcode
- Git

### Installation

```bash
# Clone repository
git clone https://github.com/YOUR_REPO/medaad.git
cd medaad

# Install dependencies
flutter pub get

# Run on device
flutter run
```

---

## 📱 Platform Setup

### Android
```bash
cd android
./gradlew clean
cd ..
flutter run
```

### iOS
```bash
cd ios
pod install
cd ..
open ios/Runner.xcworkspace
# اضغط Run في Xcode
```

**للتفاصيل الكاملة، راجع:**
- [IOS_BUILD_GUIDE.md](IOS_BUILD_GUIDE.md) - دليل بناء iOS
- [IOS_TECHNICAL_DOCS.md](IOS_TECHNICAL_DOCS.md) - التوثيق التقني

---

## 🧪 Testing

### Unit Tests
```bash
flutter test
```

### Integration Tests
```bash
flutter test integration_test/
```

### Widget Tests
```bash
flutter test test/widget_test.dart
```

---

## 🔧 Configuration

### Firebase Setup
1. إنشاء مشروع على Firebase Console
2. تحميل `google-services.json` (Android)
3. تحميل `GoogleService-Info.plist` (iOS)
4. وضعهم في المجلدات المناسبة

### API Configuration
في `lib/core/network/api_config.dart`:
```dart
class ApiConfig {
  static const String baseUrl = 'https://your-api.com';
  static const String apiKey = 'YOUR_API_KEY';
}
```

---

## 📊 Performance

- **App Size:** ~50MB (Android), ~60MB (iOS)
- **Startup Time:** <2 seconds
- **Video Streaming:** Adaptive bitrate
- **Encryption Speed:** Real-time
- **Memory Usage:** Optimized

---

## 🔐 Security Measures

1. **Screen Protection**: Prevents screenshots and recordings
2. **File Encryption**: AES-256 encryption for all downloads
3. **Secure Storage**: iOS Keychain / Android KeyStore
4. **Network Security**: SSL Pinning (optional)
5. **Code Obfuscation**: Enabled in release builds

---

## 📝 License

Copyright © 2024 Amr AI. All rights reserved.

This software is proprietary and confidential.

---

## 👥 Team

**Amr AI Technical Team**

- **Lead Developer:** Amr AI
- **Contact:** 01090991769
- **Email:** support@amrai.tech
- **Website:** www.amrai.tech

---

## 📞 Support

للدعم الفني والاستفسارات:

- **Phone:** 01090991769
- **Email:** support@amrai.tech
- **Working Hours:** 9 AM - 6 PM (Sun-Thu)

---

## 🎯 Roadmap

### Version 1.1 (Coming Soon)
- [ ] دعم Live Streaming
- [ ] نظام إشعارات Push
- [ ] Dark Mode محسن
- [ ] مزامنة متعددة الأجهزة

### Version 1.2
- [ ] دعم Augmented Reality
- [ ] نظام مكافآت
- [ ] تحديات تفاعلية
- [ ] دعم Web Platform

---

## 🌟 Acknowledgments

- Flutter Team
- Firebase Team
- جميع مساهمي المكتبات المستخدمة

---

<div align="center">

**Built with ❤️ by Amr AI**

**Quality is not an act, it is a habit**

[Report Bug](https://github.com/YOUR_REPO/issues) · 
[Request Feature](https://github.com/YOUR_REPO/issues) · 
[Documentation](IOS_BUILD_GUIDE.md)

**Contact: 01090991769**

</div>
