import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

class FileCryptoService {
  static final _algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
  static const int NONCE_LENGTH = 12;
  
  // ✅ تحديد حجم الأجزاء (32 كيلوبايت لكل جزء)
  static const int CHUNK_SIZE = 32 * 1024; 
  // ✅ الحجم الكلي للجزء المشفر (12 بايت للـ Nonce + البيانات)
  static const int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE;

  static SecretKey? _key;
  static final _storage = const FlutterSecureStorage();

  static Future<void> init() async {
    if (_key != null) return;

    String? storedKey = await _storage.read(key: 'docs_chacha_key');
    List<int> keyBytes;

    if (storedKey == null) {
      keyBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
      await _storage.write(key: 'docs_chacha_key', value: base64Encode(keyBytes));
    } else {
      keyBytes = base64Decode(storedKey);
    }

    _key = SecretKey(keyBytes);
  }

  /// ✅ التعديل الجديد: تشفير الملف بنظام الأجزاء (Chunks)
  /// هذا التنسيق يسمح لنا بالذهاب إلى أي مكان في الملف وفك تشفير جزء صغير منه فوراً
  static Future<void> encryptFileChunked(String inputPath, String outputPath) async {
    await init();
    
    final inFile = File(inputPath);
    final outFile = File(outputPath);
    final rafRead = await inFile.open(mode: FileMode.read);
    final iosWrite = outFile.openWrite();

    try {
      final int fileLength = await inFile.length();
      int currentPos = 0;

      while (currentPos < fileLength) {
        // قراءة جزء من البيانات الخام
        final chunk = await rafRead.read(CHUNK_SIZE);
        
        // توليد Nonce فريد لكل جزء لزيادة الأمان
        final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
        
        // تشفير هذا الجزء فقط
        final secretBox = await _algorithm.encrypt(
          chunk,
          secretKey: _key!,
          nonce: nonce,
        );

        // كتابة الـ Nonce ثم البيانات المشفرة في الملف النهائي
        iosWrite.add(nonce);
        iosWrite.add(secretBox.cipherText);
        
        currentPos += chunk.length;
      }
    } finally {
      await rafRead.close();
      await iosWrite.close();
    }
  }

  /// ✅ التعديل الجديد: فك تشفير نطاق محدد من البايتات "عند الطلب"
  /// تُستخدم هذه الدالة من قبل مشغل الـ PDF لقراءة الأجزاء المطلوبة فقط للعرض
  static Future<Uint8List> readAndDecryptRange(File encryptedFile, int offset, int length) async {
    await init();
    final raf = await encryptedFile.open(mode: FileMode.read);
    
    try {
      // 1. تحديد أي جزء (Chunk) نحتاج لقراءته بناءً على الـ offset
      int chunkIndex = offset ~/ CHUNK_SIZE;
      int internalOffset = offset % CHUNK_SIZE;
      
      // 2. الانتقال إلى بداية الجزء المشفر في الملف
      await raf.setPosition(chunkIndex * ENCRYPTED_CHUNK_SIZE);
      
      // 3. قراءة الكتلة المشفرة كاملة (Nonce + Ciphertext)
      final encryptedData = await raf.read(ENCRYPTED_CHUNK_SIZE);
      if (encryptedData.isEmpty) return Uint8List(0);

      final nonce = encryptedData.sublist(0, NONCE_LENGTH);
      final cipherText = encryptedData.sublist(NONCE_LENGTH);

      // 4. فك تشفير هذا الجزء الصغير في الذاكرة
      final decrypted = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac.empty),
        secretKey: _key!,
      );

      final decryptedBytes = Uint8List.fromList(decrypted);
      
      // 5. استخراج البيانات المطلوبة بالضبط من داخل الجزء المفكوك
      int end = (internalOffset + length) > decryptedBytes.length 
          ? decryptedBytes.length 
          : (internalOffset + length);
          
      return decryptedBytes.sublist(internalOffset, end);
    } finally {
      await raf.close();
    }
  }

  // ملاحظة: تم الاحتفاظ بالدوال القديمة للتوافق، ولكن يُنصح باستخدام encryptFileChunked للـ PDF
  static Future<void> encryptFile(String inputPath, String outputPath) async {
    await init();
    final inFile = File(inputPath);
    final outFile = File(outputPath);
    final ios = outFile.openWrite();
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
    ios.add(nonce);
    final stream = _algorithm.encryptStream(
      inFile.openRead(),
      secretKey: _key!,
      nonce: nonce,
      onMac: (mac) {},
    );
    await ios.addStream(stream);
    await ios.close();
  }
}
