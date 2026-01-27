# Firebase Configuration for iOS - Medaad

## 🔥 إعداد Firebase على iOS

### الخطوة 1: إنشاء مشروع Firebase
1. اذهب إلى [Firebase Console](https://console.firebase.google.com/)
2. أنشئ مشروع جديد أو استخدم الموجود
3. اسم المشروع: `medaad-learning`

### الخطوة 2: إضافة تطبيق iOS

1. في Firebase Console، اضغط على أيقونة iOS
2. املأ البيانات:
   - **iOS Bundle ID:** `com.amrai.medaad` (يجب أن يطابق Bundle ID في Xcode)
   - **App nickname:** Medaad iOS
   - **App Store ID:** (اختياري - سيكون متاحاً بعد النشر)

3. اضغط **Register app**

### الخطوة 3: تحميل GoogleService-Info.plist

1. بعد التسجيل، حمّل ملف `GoogleService-Info.plist`
2. في Xcode:
   - افتح `ios/Runner.xcworkspace`
   - اسحب ملف `GoogleService-Info.plist` إلى مجلد `Runner`
   - تأكد من تحديد "Copy items if needed"
   - تأكد من تحديد Target: "Runner"

### الخطوة 4: تعديل AppDelegate.swift

الملف موجود بالفعل في `ios/Runner/AppDelegate.swift` ومحدث بالكامل.

إذا احتجت التعديل يدوياً، أضف في أول الملف:
```swift
import Firebase
```

وفي دالة `application`:
```swift
FirebaseApp.configure()
```

### الخطوة 5: تحديث Podfile

الملف موجود في `ios/Podfile` ومُعد بالكامل.

### الخطوة 6: تثبيت Pods

```bash
cd ios
pod install
cd ..
```

### الخطوة 7: تفعيل خدمات Firebase

في Firebase Console، فعّل:

#### 1. Crashlytics
- اذهب إلى **Crashlytics** في القائمة
- اضغط **Enable Crashlytics**
- اتبع الخطوات

#### 2. Authentication (إذا لزم الأمر)
- اذهب إلى **Authentication**
- فعّل طرق تسجيل الدخول المطلوبة:
  - Email/Password
  - Google Sign-In (اختياري)
  - Phone Authentication (اختياري)

#### 3. Cloud Firestore (إذا لزم الأمر)
- اذهب إلى **Firestore Database**
- اضغط **Create database**
- اختر Mode (Test أو Production)

#### 4. Storage (لتخزين الإيصالات)
- اذهب إلى **Storage**
- اضغط **Get started**
- قبول القواعد الافتراضية

### الخطوة 8: التحقق من التكامل

بعد البناء، تحقق من:
1. فتح Xcode Console
2. ابحث عن رسائل Firebase:
```
[Firebase/Core][I-COR000001] Configuring the default app.
[Firebase/Crashlytics] Successfully initialized
```

---

## 🔐 إعدادات الأمان في Firebase

### 1. Firestore Security Rules (مثال)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Courses - public read, admin write
    match /courses/{courseId} {
      allow read: if request.auth != null;
      allow write: if request.auth.token.admin == true;
    }
    
    // Subscription requests - user can create, admin can read all
    match /subscription_requests/{requestId} {
      allow create: if request.auth != null;
      allow read: if request.auth != null && 
                    (request.auth.uid == resource.data.userId || 
                     request.auth.token.admin == true);
    }
  }
}
```

### 2. Storage Security Rules (مثال)

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Receipt images - authenticated users can upload
    match /receipts/{userId}/{allPaths=**} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && 
                     request.auth.uid == userId &&
                     request.resource.size < 10 * 1024 * 1024; // Max 10MB
    }
    
    // Course content - admins only
    match /courses/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth.token.admin == true;
    }
  }
}
```

---

## 📱 اختبار Firebase على iOS

### 1. Crashlytics Test

أضف هذا الكود في التطبيق مؤقتاً:
```swift
import FirebaseCrashlytics

// Force a crash to test
// fatalError("Test crash for Crashlytics")

// Or log a non-fatal error
Crashlytics.crashlytics().log("Test error message")
```

### 2. تحقق من Dashboard

- افتح Firebase Console
- اذهب إلى Crashlytics
- يجب أن ترى البيانات خلال دقائق

---

## 🚨 استكشاف المشاكل الشائعة

### المشكلة: "GoogleService-Info.plist not found"

**الحل:**
1. تأكد من وجود الملف في `ios/Runner/`
2. تأكد من إضافته للـ Target في Xcode
3. Clean Build: Product → Clean Build Folder
4. أعد البناء

### المشكلة: "Firebase not initialized"

**الحل:**
```swift
// في AppDelegate.swift، تأكد من:
import Firebase

override func application(...) -> Bool {
    FirebaseApp.configure() // هذا السطر مهم جداً
    ...
}
```

### المشكلة: Bundle ID mismatch

**الحل:**
1. تحقق من Bundle ID في Xcode (Runner → General)
2. تحقق من Bundle ID في Firebase Console
3. يجب أن يكونا متطابقين تماماً
4. إذا غيرت Bundle ID، حمّل `GoogleService-Info.plist` جديد

---

## 📞 للمساعدة

**Amr AI Technical Team**  
Phone/WhatsApp: 01090991769  
Email: support@amr-ai.com

---

**✅ بعد إكمال هذه الخطوات، Firebase سيكون جاهزاً بالكامل على iOS!**
