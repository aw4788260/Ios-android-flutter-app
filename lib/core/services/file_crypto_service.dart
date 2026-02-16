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

  /// ✅ دالة جديدة: تشفير جزء من البيانات فوراً أثناء التحميل المباشر (تستخدم للفيديوهات V2)
  static Future<Uint8List> encryptChunkOnTheFly(List<int> data) async {
    await init();
    // توليد Nonce فريد لهذه الكتلة
    final nonce = List<int>.generate(NONCE_LENGTH, (i) => Random.secure().nextInt(256));
    
    // تشفير البيانات
    final secretBox = await _algorithm.encrypt(
      data,
      secretKey: _key!,
      nonce: nonce,
    );
    
    // دمج الـ Nonce مع البيانات المشفرة
    final builder = BytesBuilder(copy: false);
    builder.add(nonce);
    builder.add(secretBox.cipherText);
    
    return builder.toBytes();
  }

  /// ✅ تشفير الملف بالكامل بنظام الأجزاء (Chunks)
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

  /// ✅ التعديل الجوهري: دعم قراءة البيانات عبر حدود الكتل المتعددة
  /// هذه الدالة تقوم بتجميع البيانات المطلوبة حتى لو كانت موزعة على أكثر من جزء مشفر
  static Future<Uint8List> readAndDecryptRange(File encryptedFile, int offset, int length) async {
    await init();
    final raf = await encryptedFile.open(mode: FileMode.read);
    
    // استخدام BytesBuilder لتجميع البيانات من عدة كتل بكفاءة
    final builder = BytesBuilder(copy: false);
    
    try {
      final int fileSize = await encryptedFile.length();
      int currentReadOffset = offset;
      int remainingLength = length;

      // حلقة تكرارية لجمع البيانات حتى نغطي الطول المطلوب (length) كاملاً
      while (remainingLength > 0) {
        // 1. تحديد أي كتلة (Chunk) نحن فيها الآن بناءً على الإزاحة الحالية
        int chunkIndex = currentReadOffset ~/ CHUNK_SIZE;
        
        // 2. حساب مكان بداية هذه الكتلة في الملف المشفر
        int chunkStartInFile = chunkIndex * ENCRYPTED_CHUNK_SIZE;
        
        // إذا وصلنا لنهاية الملف الحقيقي نتوقف
        if (chunkStartInFile >= fileSize) break;

        // 3. الانتقال وقراءة الكتلة المشفرة الحالية
        await raf.setPosition(chunkStartInFile);
        
        // نقرأ الحد الأقصى المتوقع للكتلة المشفرة (قد تكون الأخيرة أصغر)
        final encryptedBlock = await raf.read(ENCRYPTED_CHUNK_SIZE);
        
        // إذا لم نجد بيانات كافية (أقل من حجم الـ Nonce)، نتوقف
        if (encryptedBlock.isEmpty || encryptedBlock.length <= NONCE_LENGTH) break;

        // 4. استخراج Nonce والبيانات وفك التشفير لهذه الكتلة
        final nonce = encryptedBlock.sublist(0, NONCE_LENGTH);
        final cipherText = encryptedBlock.sublist(NONCE_LENGTH);

        final decryptedChunk = await _algorithm.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac.empty),
          secretKey: _key!,
        );

        // 5. تحديد الجزء المطلوب بالضبط من داخل هذه الكتلة المفكوكة
        // حساب الإزاحة النسبية داخل الكتلة الحالية
        int startInChunk = currentReadOffset % CHUNK_SIZE;
        
        // حساب كم تبقى من بيانات صالحة في هذه الكتلة بدءاً من الإزاحة النسبية
        int availableInChunk = decryptedChunk.length - startInChunk;
        
        if (availableInChunk <= 0) break; // حماية إضافية

        // نأخذ الكمية الأقل بين: ما تبقى في الكتلة، أو ما تبقى من الطلب الكلي
        int bytesToTake = min(remainingLength, availableInChunk);
        
        // إضافة البيانات المستخلصة إلى المجمع النهائي
        builder.add(decryptedChunk.sublist(startInChunk, startInChunk + bytesToTake));

        // تحديث العدادات للدورة القادمة (للانتقال للكتلة التالية إذا لزم الأمر)
        currentReadOffset += bytesToTake;
        remainingLength -= bytesToTake;
      }

      return builder.toBytes();
      
    } catch (e) {
      // في حالة حدوث خطأ، نعيد مصفوفة فارغة ليتعامل معها العارض بدلاً من تحطيم التطبيق
      return Uint8List(0);
    } finally {
      await raf.close();
    }
  }

  // دالة التشفير القديمة (مبقاة للتوافق مع الملفات القديمة أو الفيديوهات إن وجدت)
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
