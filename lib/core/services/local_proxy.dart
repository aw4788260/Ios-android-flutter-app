import 'dart:io';
import 'dart:async';
import 'dart:isolate'; 
import 'dart:math';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:encrypt/encrypt.dart' as encrypt; 
import '../utils/encryption_helper.dart';
import 'file_crypto_service.dart'; // ✅ استدعاء خدمة التشفير الجديدة

class LocalProxyService {
  static final LocalProxyService _instance = LocalProxyService._internal();
  
  factory LocalProxyService() {
    return _instance;
  }
  
  LocalProxyService._internal();

  // Separate processing threads
  Isolate? _videoServerIsolate;
  Isolate? _audioServerIsolate;
  
  int _videoPort = 0;
  int _audioPort = 0;
  
  // ✅ إضافة متغير التوكن
  String _authToken = "";

  int get videoPort => _videoPort;
  int get audioPort => _audioPort;
  // ✅ Getter للوصول للتوكن من الملفات الأخرى
  String get authToken => _authToken;
  
  ReceivePort? _videoReceivePort;
  ReceivePort? _audioReceivePort;
  
  Completer<void>? _readyCompleter;

  Future<void> start() async {
    // Keep-Alive: If server is already running, do nothing and return immediately
    if (_videoServerIsolate != null && _audioServerIsolate != null && _videoPort != 0 && _audioPort != 0) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        await _readyCompleter!.future;
      }
      return;
    }

    _readyCompleter = Completer<void>();

    try {
      await EncryptionHelper.init();
      String keyBase64 = EncryptionHelper.key.base64;
      
      // ✅ 1. توليد توكن عشوائي آمن عند بدء التشغيل
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      _authToken = values.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      print('🔒 [SECURITY] Proxy Auth Token Generated');

      // 2. Start Video Server (Port 0 = Random)
      _videoReceivePort = ReceivePort();
      _videoServerIsolate = await Isolate.spawn(
        _proxyServerEntryPoint, 
        // ✅ تمرير التوكن للـ Isolate
        _ProxyInitData(_videoReceivePort!.sendPort, keyBase64, "VideoIsolate", _authToken)
      );
      
      // Wait for ready message with port number
      await for (final message in _videoReceivePort!) {
        if (message is String && message.startsWith("READY:")) {
          _videoPort = int.parse(message.split(':')[1]);
          print('🔍 [DIAGNOSIS] Video Proxy Started on dynamic port: $_videoPort');
          break; 
        } else if (message.toString().startsWith("ERROR")) {
          throw Exception("Video Proxy Failed: $message");
        }
      }

      // 3. Start Audio Server (Port 0 = Random)
      _audioReceivePort = ReceivePort();
      _audioServerIsolate = await Isolate.spawn(
        _proxyServerEntryPoint, 
        // ✅ تمرير التوكن للـ Isolate
        _ProxyInitData(_audioReceivePort!.sendPort, keyBase64, "AudioIsolate", _authToken)
      );

      // Wait for ready message with port number
      await for (final message in _audioReceivePort!) {
        if (message is String && message.startsWith("READY:")) {
          _audioPort = int.parse(message.split(':')[1]);
          print('🔍 [DIAGNOSIS] Audio Proxy Started on dynamic port: $_audioPort');
          break; 
        } else if (message.toString().startsWith("ERROR")) {
          throw Exception("Audio Proxy Failed: $message");
        }
      }

      _readyCompleter?.complete();
      
    } catch (e) {
      print("❌ Proxy Launch Error: $e");
      _readyCompleter?.completeError(e);
      stop();
    }
  }

  void stop() {
    _readyCompleter = null;
    _videoPort = 0;
    _audioPort = 0;
    _authToken = ""; // تصفير التوكن
    
    if (_videoServerIsolate != null) {
        print('🛑 Stopping Video Proxy');
        _videoReceivePort?.close();
        _videoServerIsolate?.kill(priority: Isolate.immediate);
        _videoServerIsolate = null;
    }

    if (_audioServerIsolate != null) {
        print('🛑 Stopping Audio Proxy');
        _audioReceivePort?.close();
        _audioServerIsolate?.kill(priority: Isolate.immediate);
        _audioServerIsolate = null;
    }
  }
}

class _ProxyInitData {
  final SendPort sendPort;
  final String keyBase64;
  final String name;
  final String authToken; // ✅ إضافة حقل التوكن

  _ProxyInitData(this.sendPort, this.keyBase64, this.name, this.authToken);
}

void _proxyServerEntryPoint(_ProxyInitData initData) async {
   try {
     final key = encrypt.Key.fromBase64(initData.keyBase64);
     final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
     
     final router = Router();
     // ✅ تمرير التوكن لدالة المعالجة
     router.get('/video', (Request req) => _handleRequest(req, encrypter, initData.name, initData.authToken));
     router.head('/video', (Request req) => _handleRequest(req, encrypter, initData.name, initData.authToken));
     
     // Use port 0 to let the system choose an available port
     final server = await shelf_io.serve(
       router, 
       InternetAddress.loopbackIPv4, // ✅ إغلاق الثغرة: الاستماع لـ 127.0.0.1 فقط
       0, // Dynamic Port
       shared: false
     );
     
     server.autoCompress = false;
     server.idleTimeout = const Duration(seconds: 60);
     
     // Send the actual port number to the main thread
     initData.sendPort.send("READY:${server.port}");
     
   } catch (e) {
     initData.sendPort.send("ERROR: $e");
   }
}

Future<Response> _handleRequest(Request request, encrypt.Encrypter encrypter, String isolateName, String expectedToken) async {
  final requestStopwatch = Stopwatch()..start(); 
  
  try {
    // ✅ التحقق من التوكن قبل أي شيء
    final requestToken = request.url.queryParameters['token'];
    if (requestToken == null || requestToken != expectedToken) {
      print("⛔ [$isolateName] Unauthorized Access Attempt!");
      return Response.forbidden('Access Denied: Invalid Token');
    }

    final pathParam = request.url.queryParameters['path'];
    if (pathParam == null) return Response.notFound('Path missing');

    // 🔥 تم التعديل: إزالة Uri.decodeComponent لأن shelf تقوم بفك التشفير تلقائياً
    final decodedPath = pathParam; 
    
    final file = File(decodedPath);
    
    if (!await file.exists()) {
      return Response.notFound('File not found');
    }

    String contentType = 'video/mp4'; 
    if (decodedPath.contains('aud_')) {
      contentType = 'audio/mp4';
    } else if (decodedPath.toLowerCase().contains('.pdf')) {
      contentType = 'application/pdf';
    }

    final encryptedLength = await file.length();
    
    // ✅ التعرف على إصدار التشفير (القديم V1 مقابل الجديد V2)
    bool isV2 = decodedPath.endsWith('_v2.enc') || decodedPath.endsWith('.pdf.enc');
    int originalFileSize;

    if (isV2) {
       // --- نظام ChaCha20 الجديد ---
       final int CHUNK_SIZE = FileCryptoService.CHUNK_SIZE; // 32KB
       final int NONCE_LENGTH = FileCryptoService.NONCE_LENGTH; // 12 bytes
       final int ENCRYPTED_CHUNK_SIZE = NONCE_LENGTH + CHUNK_SIZE;
       
       int numChunks = (encryptedLength / ENCRYPTED_CHUNK_SIZE).ceil();
       originalFileSize = encryptedLength - (numChunks * NONCE_LENGTH);
    } else {
       // --- النظام القديم AES ---
       final int CHUNK_SIZE = EncryptionHelper.CHUNK_SIZE; 
       const int IV_LENGTH = 12;
       const int TAG_LENGTH = 16;
       final int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH; 
       
       final int totalChunks = (encryptedLength / ENCRYPTED_CHUNK_SIZE).ceil();
       if (totalChunks == 0) return Response.ok('');
       
       final int plainChunkSize = CHUNK_SIZE;
       final int overhead = ENCRYPTED_CHUNK_SIZE - plainChunkSize; 
       originalFileSize = ((totalChunks - 1) * plainChunkSize) + max(0, (encryptedLength - ((totalChunks - 1) * ENCRYPTED_CHUNK_SIZE)) - overhead);
    }

    final rangeHeader = request.headers['range'];
    int start = 0;
    int end = originalFileSize - 1;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      if (parts.isNotEmpty) start = int.tryParse(parts[0]) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) end = int.tryParse(parts[1]) ?? originalFileSize - 1;
    }

    if (start >= originalFileSize) {
       return Response(416, body: 'Invalid Range', headers: {'Content-Range': 'bytes */$originalFileSize'});
    }
    
    final contentLength = end - start + 1;

    print("🔍 [PROXY_REQ] $isolateName | Range: $start-$end | V2: $isV2 | Processing: ${requestStopwatch.elapsedMilliseconds}ms");

    final Map<String, Object> headers = {
        'Content-Type': contentType, 
        'Content-Length': contentLength.toString(),
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*', // يمكن تقييدها أكثر إذا لزم الأمر
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Connection': 'keep-alive',
    };

    if (request.method == 'HEAD') {
      return Response.ok(null, headers: headers);
    }

    headers['Content-Range'] = 'bytes $start-$end/$originalFileSize';

    return Response(
      206, 
      body: isV2 
          ? _createDecryptedStreamV2(file, start, end, isolateName)
          : _createDecryptedStream(file, start, end, encrypter, isolateName),
      headers: headers,
    );

  } catch (e) {
    print("[$isolateName] Request Error: $e");
    return Response.internalServerError(body: 'Proxy Error');
  }
}

// ✅ دالة جديدة لمعالجة وتشغيل الفيديوهات بنظام ChaCha20 (V2) السريع
Stream<List<int>> _createDecryptedStreamV2(File file, int reqStart, int reqEnd, String isolateName) async* {
  final streamStopwatch = Stopwatch()..start(); 
  final int requiredLength = reqEnd - reqStart + 1;
  int totalSent = 0;
  
  try {
    const int MAX_READ_SIZE = 512 * 1024; // فك التشفير في كتل 512 كيلوبايت للحفاظ على الرام
    int currentOffset = reqStart;
    
    while (currentOffset <= reqEnd) {
      if (totalSent >= requiredLength) break;
      
      int readLen = min(MAX_READ_SIZE, reqEnd - currentOffset + 1);
      
      // نستخدم الدالة من FileCryptoService التي تعالج الكتل المعقدة تلقائياً
      Uint8List data = await FileCryptoService.readAndDecryptRange(file, currentOffset, readLen);
      
      if (data.isEmpty) break;
      
      yield data;
      totalSent += data.length;
      currentOffset += data.length;
    }
    print("✅ [PROXY_V2_DONE] $isolateName | Total sent: $totalSent bytes | Time: ${streamStopwatch.elapsedMilliseconds}ms");
  } catch(e) {
      print("Stream V2 Error: $e");
  } finally {
    // إرسال بايتات فارغة إذا انقطع الاتصال فجأة لمنع تعليق المشغل
    if (totalSent < requiredLength) {
        int missingBytes = requiredLength - totalSent;
        if (missingBytes > 0 && missingBytes < 1024 * 1024) { 
           yield Uint8List(missingBytes);
        }
    }
  }
}

// دالة التشغيل القديمة للملفات المحملة مسبقاً بنظام AES (V1)
Stream<List<int>> _createDecryptedStream(File file, int reqStart, int reqEnd, encrypt.Encrypter encrypter, String isolateName) async* {
  final streamStopwatch = Stopwatch()..start(); 
  RandomAccessFile? raf;
  int totalSent = 0; 
  final int requiredLength = reqEnd - reqStart + 1;

  try {
    raf = await file.open(mode: FileMode.read);
    
    final int CHUNK_SIZE = EncryptionHelper.CHUNK_SIZE;
    
    const int IV_LENGTH = 12;
    const int TAG_LENGTH = 16;
    final int ENCRYPTED_CHUNK_SIZE = IV_LENGTH + CHUNK_SIZE + TAG_LENGTH;

    int startChunkIndex = reqStart ~/ CHUNK_SIZE;
    int endChunkIndex = reqEnd ~/ CHUNK_SIZE;
    final fileLen = await file.length();
    
    int loopCount = 0;
    
    int totalReadTime = 0;
    int totalDecryptTime = 0;
    int chunksProcessed = 0;

    for (int i = startChunkIndex; i <= endChunkIndex; i++) {
      if (totalSent >= requiredLength) break;

      if (++loopCount % 32 == 0) {
          await Future.delayed(Duration.zero);
      }

      final chunkTimer = Stopwatch()..start();

      int seekPos = i * ENCRYPTED_CHUNK_SIZE;
      if (seekPos >= fileLen) break;

      await raf.setPosition(seekPos);
      
      int bytesToRead = min(ENCRYPTED_CHUNK_SIZE, fileLen - seekPos);
      if (bytesToRead <= IV_LENGTH) break;

      final readStart = chunkTimer.elapsedMicroseconds;
      Uint8List encryptedBlock = await raf.read(bytesToRead);
      final readEnd = chunkTimer.elapsedMicroseconds;
      totalReadTime += (readEnd - readStart);

      Uint8List outputBlock;

      try {
        if (encryptedBlock.length < IV_LENGTH) {
             outputBlock = Uint8List(0);
        } else {
            final decryptStart = chunkTimer.elapsedMicroseconds;
            final iv = encrypt.IV(encryptedBlock.sublist(0, IV_LENGTH));
            final cipherBytes = encryptedBlock.sublist(IV_LENGTH);
            
            final decrypted = encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);
            
            outputBlock = (decrypted is Uint8List) ? decrypted : Uint8List.fromList(decrypted);
            final decryptEnd = chunkTimer.elapsedMicroseconds;
            totalDecryptTime += (decryptEnd - decryptStart);
        }

      } catch (e) {
         int expectedSize = (bytesToRead == ENCRYPTED_CHUNK_SIZE) 
             ? CHUNK_SIZE 
             : max(0, bytesToRead - IV_LENGTH - TAG_LENGTH);
         outputBlock = Uint8List(expectedSize);
      }

      if (outputBlock.isNotEmpty) {
        int blockStartInPlain = i * CHUNK_SIZE;
        int sliceStart = max(0, reqStart - blockStartInPlain);
        int sliceEnd = min(outputBlock.length, reqEnd - blockStartInPlain + 1);

        if (sliceStart < sliceEnd) {
          final dataChunk = outputBlock.sublist(sliceStart, sliceEnd);
          totalSent += dataChunk.length;
          yield dataChunk;
          chunksProcessed++;
        }
      }
      
      if (chunksProcessed == 1 || chunksProcessed % 50 == 0) {
          // Optional logging
          // print("📊 [PROXY_STATS] $isolateName | Chunk #$chunksProcessed");
      }
    }
    
    print("✅ [PROXY_DONE] $isolateName | Total sent: $totalSent bytes | Total Time: ${streamStopwatch.elapsedMilliseconds}ms");

  } catch(e) {
      print("Stream Error: $e");
  } finally {
    if (totalSent < requiredLength) {
        int missingBytes = requiredLength - totalSent;
        if (missingBytes > 0 && missingBytes < 1024 * 1024) { 
           yield Uint8List(missingBytes);
        }
    }
    await raf?.close();
  }
}
