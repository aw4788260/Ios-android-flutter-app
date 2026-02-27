import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/file_crypto_service.dart';
import '../../core/models/drawing_model.dart';
import '../../core/models/comment_model.dart';
import '../../core/services/storage_service.dart';
import '../../core/constants/api_constants.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfId, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- متغيرات فك التشفير ---
  File? _encryptedFile;
  int? _originalFileSize;
  String? _sessionToken;

  // --- متغيرات العرض الأونلاين ---
  String? _onlineUrl;
  Map<String, String>? _onlineHeaders;

  bool _loading = true;
  String _loadingMessage = "جار التحقق من الملف...";
  String? _error;
  bool _isOffline = false;
  String _watermarkText = '';

  // --- أدوات الرسم والتعليقات ---
  bool _isDrawingMode = false;
  int _selectedTool = 0; // 0=Pen, 1=Highlighter, 2=Eraser, 3=Comment
  Color _selectedColor = Colors.red;
  double _penSize = 0.003;
  double _highlightSize = 0.035;
  double _eraserSize = 0.04;

  Map<int, List<DrawingLine>> _pageDrawings = {};
  Map<int, List<CommentModel>> _pageComments = {};

  DrawingLine? _currentLine;
  int _activePage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _sessionToken = _generateSecureToken();
    _initWatermarkText();
    _preparePdf();
  }

  @override
  void dispose() {
    if (_isOffline) _saveAnnotationsToHive();
    super.dispose();
  }

  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  Future<int> _customRead(Uint8List buffer, int position, int size) async {
    try {
      if (_sessionToken == null) throw Exception("Unauthorized access context");
      if (_encryptedFile == null) throw Exception("File not initialized");

      final decryptedData = await FileCryptoService.readAndDecryptRange(
          _encryptedFile!, position, size);

      if (decryptedData.isNotEmpty) {
        buffer.setRange(0, decryptedData.length, decryptedData);
        return decryptedData.length;
      }
      return 0;
    } catch (e) {
      debugPrint("Secure Read Error: $e");
      return 0;
    }
  }

  Future<void> _initWatermarkText() async {
    String displayText = '';
    if (AppState().userData != null) {
      displayText = AppState().userData!['phone'] != null
          ? AppState().userData!['phone']
          : '';
    }
    if (displayText.isEmpty) {
      try {
        final box = await StorageService.openBox('auth_box');
        displayText = box.get('phone') ?? box.get('first_name') ?? '';
      } catch (e) {
        debugPrint("Error fetching watermark: $e");
      }
    }
    if (mounted) {
      setState(() => _watermarkText = displayText.isNotEmpty
          ? displayText
          : AppState().userData!['username'] ?? 'Unknown User');
    }
  }

  // ✅ حفظ الرسم والتعليقات معاً
  Future<void> _saveAnnotationsToHive() async {
    try {
      final box = await StorageService.openBox('pdf_drawings_db');

      // حفظ الرسومات
      for (var entry in _pageDrawings.entries) {
        if (entry.value.isNotEmpty) {
          final serialized = entry.value.map((l) => l.toJson()).toList();
          await box.put('${widget.pdfId}_${entry.key}', serialized);
        }
      }

      // حفظ التعليقات
      for (var entry in _pageComments.entries) {
        if (entry.value.isNotEmpty) {
          final serializedComments =
              entry.value.map((c) => c.toJson()).toList();
          await box.put(
              '${widget.pdfId}_${entry.key}_comments', serializedComments);
        } else {
          await box.delete('${widget.pdfId}_${entry.key}_comments');
        }
      }
    } catch (_) {}
  }

  // ✅ جلب الرسومات والتعليقات معاً
  Future<void> _loadAnnotationsForPage(int pageNumber) async {
    final box = await StorageService.openBox('pdf_drawings_db');

    // جلب الرسومات
    if (!_pageDrawings.containsKey(pageNumber)) {
      final dynamic data = box.get('${widget.pdfId}_$pageNumber');
      List<DrawingLine> lines = [];
      if (data != null) {
        lines = (data as List<dynamic>)
            .map((e) => DrawingLine.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      _pageDrawings[pageNumber] = lines;
    }

    // جلب التعليقات
    if (!_pageComments.containsKey(pageNumber)) {
      final dynamic commentData =
          box.get('${widget.pdfId}_${pageNumber}_comments');
      List<CommentModel> comments = [];
      if (commentData != null) {
        comments = (commentData as List<dynamic>)
            .map((e) => CommentModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      _pageComments[pageNumber] = comments;
    }
  }

  Future<void> _preparePdf() async {
    setState(() {
      _loading = true;
      _loadingMessage = "جار تهيئة الحماية...";
    });

    try {
      await FileCryptoService.init();

      final downloadsBox = await StorageService.openBox('downloads_box');
      final downloadItem = downloadsBox.get('pdf_${widget.pdfId}');

      if (downloadItem != null && downloadItem['path'] != null) {
        final file = File(downloadItem['path']);
        if (await file.exists()) {
          final totalSize = await file.length();

          int numChunks =
              (totalSize / FileCryptoService.ENCRYPTED_CHUNK_SIZE).ceil();
          int originalSize =
              totalSize - (numChunks * FileCryptoService.NONCE_LENGTH);

          if (mounted) {
            setState(() {
              _isOffline = true;
              _encryptedFile = file;
              _originalFileSize = originalSize;
              _loading = false;
            });
          }
          return;
        }
      }

      setState(() {
        _isOffline = false;
        _loadingMessage = "جار التحميل المباشر...";
      });

      var box = await StorageService.openBox('auth_box');
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      _onlineHeaders = {
        'Authorization': 'Bearer $token',
        'x-device-id': deviceId ?? '',
        'x-app-secret': const String.fromEnvironment('APP_SECRET'),
      };

      _onlineUrl =
          '${ApiConstants.apiUrl}/secure/get-pdf?pdfId=${widget.pdfId}';

      if (mounted) setState(() => _loading = false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: "PDF Secure Load Failed");
      if (mounted)
        setState(() {
          _error = "فشل فتح الملف المحمي.";
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoadingView();
    if (_error != null) return _buildErrorView();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundPrimary,
      endDrawer: _buildPageDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _isOffline && _encryptedFile != null && _originalFileSize != null
              ? PdfViewer.custom(
                  fileSize: _originalFileSize!,
                  read: _customRead,
                  sourceName: _encryptedFile!.path,
                  controller: _pdfController,
                  params: _buildPdfParams(),
                )
              : PdfViewer.uri(
                  Uri.parse(_onlineUrl!),
                  headers: _onlineHeaders,
                  controller: _pdfController,
                  params: _buildPdfParams(),
                ),
          _buildWatermark(),
          if (_isDrawingMode && _isOffline)
            Positioned(bottom: 40, left: 20, right: 20, child: _buildToolbar()),
        ],
      ),
    );
  }

  // --- Widgets ---

  Widget _buildLoadingView() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accentYellow),
            const SizedBox(height: 20),
            Text(_loadingMessage,
                style: TextStyle(
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white)),
        body: Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white))));
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Expanded(
              child: Text(widget.title,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _buildBadge(),
          if (_isOffline) ...[
            const SizedBox(width: 12),
            _buildPenIcon(),
          ]
        ],
      ),
      backgroundColor: AppColors.backgroundSecondary,
      leading: BackButton(
          color: AppColors.accentYellow,
          onPressed: () async {
            if (_isOffline) await _saveAnnotationsToHive();
            if (context.mounted) Navigator.pop(context);
          }),
      actions: [
        IconButton(
          icon: Icon(LucideIcons.list, color: AppColors.accentYellow),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ],
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isOffline
            ? Colors.green.withOpacity(0.2)
            : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: _isOffline ? Colors.green : Colors.blue, width: 1),
      ),
      child: Row(
        children: [
          Icon(_isOffline ? LucideIcons.hardDrive : LucideIcons.cloud,
              size: 12, color: _isOffline ? Colors.green : Colors.blue),
          const SizedBox(width: 4),
          Text(_isOffline ? "Offline" : "Stream",
              style: TextStyle(
                  fontSize: 10,
                  color: _isOffline ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPenIcon() {
    return GestureDetector(
      onTap: () => setState(() => _isDrawingMode = !_isDrawingMode),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: _isDrawingMode ? AppColors.accentYellow : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accentYellow.withOpacity(0.5))),
        child: Icon(LucideIcons.penTool,
            color: _isDrawingMode ? Colors.black : AppColors.accentYellow,
            size: 16),
      ),
    );
  }

  Widget _buildWatermark() {
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
                3,
                (index) => Transform.rotate(
                      angle: -0.5,
                      child: Text(
                        _watermarkText,
                        textScaler: const TextScaler.linear(2.2),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            decoration: TextDecoration.none),
                      ),
                    )),
          ),
        ),
      ),
    );
  }

  Widget _buildPageDrawer() {
    return Drawer(
      backgroundColor: AppColors.backgroundSecondary,
      width: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            child: Text("فهرس الصفحات",
                style: TextStyle(
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: _totalPages == 0
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accentYellow))
                : ListView.builder(
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      final pageNum = index + 1;
                      final isCurrent = _pdfController.pageNumber == pageNum;
                      return ListTile(
                        title: Text("صفحة $pageNum",
                            style: TextStyle(
                                color: isCurrent
                                    ? AppColors.accentYellow
                                    : AppColors.textPrimary,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        leading: Icon(LucideIcons.fileText,
                            color: isCurrent
                                ? AppColors.accentYellow
                                : AppColors.textSecondary,
                            size: 18),
                        onTap: () {
                          _pdfController.goToPage(pageNumber: pageNum);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  PdfViewerParams _buildPdfParams() {
    return PdfViewerParams(
      backgroundColor: AppColors.backgroundPrimary,
      textSelectionParams: const PdfTextSelectionParams(enabled: false),
      scrollPhysics: const BouncingScrollPhysics(),
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: CircularProgressIndicator(color: AppColors.accentYellow),
          ),
        );
      },
      onDocumentChanged: (document) {
        if (mounted) setState(() => _totalPages = document?.pages.length ?? 0);
      },
      pageOverlaysBuilder: (context, pageRect, page) {
        if (!_isOffline) return [];
        return [
          Positioned.fill(
            child: FutureBuilder(
              future: _loadAnnotationsForPage(page.pageNumber),
              builder: (context, snapshot) {
                // 1. تجهيز الرسومات
                final lines = _pageDrawings[page.pageNumber] ?? [];
                final allLines = [...lines];
                if (_isDrawingMode &&
                    _currentLine != null &&
                    _activePage == page.pageNumber) {
                  allLines.add(_currentLine!);
                }

                // 2. تجهيز التعليقات
                final comments = _pageComments[page.pageNumber] ?? [];

                return Stack(
                  children: [
                    // طبقة الرسم والخلفية (تضيف تعليقات جديدة)
                    IgnorePointer(
                      ignoring: !_isDrawingMode,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          if (_selectedTool == 3) {
                            _addComment(
                                details, context, pageRect, page.pageNumber);
                          }
                        },
                        onPanStart: (details) {
                          if (_selectedTool != 3)
                            _startStroke(details, context, pageRect, page);
                        },
                        onPanUpdate: (details) {
                          if (_selectedTool != 3)
                            _updateStroke(details, context, pageRect);
                        },
                        onPanEnd: (details) {
                          if (_selectedTool != 3) _endStroke(page);
                        },
                        child: CustomPaint(
                          painter: RelativeSketchPainter(
                              lines: allLines, pageSize: pageRect.size),
                          size: Size.infinite,
                        ),
                      ),
                    ),

                    // طبقة أيقونات التعليقات المضافة مسبقاً
                    if (_isOffline)
                      ...comments.map((comment) {
                        // استخراج اللون الأساسي والشفافية
                        Color solidColor =
                            Color(comment.color).withOpacity(1.0);
                        double currentOpacity = Color(comment.color).opacity;

                        return Positioned(
                          left: (comment.dx * pageRect.width) -
                              (20 * comment.scale),
                          top: (comment.dy * pageRect.height) -
                              (20 * comment.scale),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: _isDrawingMode ? (_) {} : null,
                            onScaleEnd: _isDrawingMode ? (_) {} : null,
                            onScaleUpdate: _isDrawingMode
                                ? (details) {
                                    setState(() {
                                      if (details.pointerCount == 1) {
                                        // ✅ سحب وتحريك فقط (تم إلغاء التكبير بالأصابع)
                                        comment.dx +=
                                            details.focalPointDelta.dx /
                                                pageRect.width;
                                        comment.dy +=
                                            details.focalPointDelta.dy /
                                                pageRect.height;
                                      }
                                    });
                                  }
                                : null,
                            onTap: () =>
                                _showCommentDialog(page.pageNumber, comment),
                            child: Transform.scale(
                              scale: comment.scale,
                              child: Opacity(
                                opacity:
                                    currentOpacity, // ✅ تطبيق الشفافية المحددة
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: AppColors.backgroundSecondary
                                          .withOpacity(0.85),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: solidColor, width: 1.5),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.4),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2))
                                      ]),
                                  child: Icon(Icons.comment_rounded,
                                      color: solidColor, size: 24),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                );
              },
            ),
          ),
        ];
      },
    );
  }

  // --- منطق التعليقات ---

  void _addComment(TapUpDetails details, BuildContext context, Rect pageRect,
      int pageNumber) {
    if (!_isDrawingMode || _selectedTool != 3) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    final newComment = CommentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: '',
      dx: relativePoint.dx,
      dy: relativePoint.dy,
      color: _selectedColor.value, // يبدأ باللون المختار مع شفافية كاملة
    );
    // تعيين الحجم الافتراضي إذا لم يكن مهيأ
    newComment.scale = 1.0;

    _showCommentDialog(pageNumber, newComment, isNew: true);
  }

  void _showCommentDialog(int pageNumber, CommentModel comment,
      {bool isNew = false}) {
    TextEditingController controller =
        TextEditingController(text: comment.text);

    showDialog(
        context: context,
        barrierDismissible: !isNew,
        builder: (ctx) => StatefulBuilder(
                // ✅ استخدام StatefulBuilder لتحديث أشرطة التحكم فوراً
                builder: (context, setDialogState) {
              return AlertDialog(
                  backgroundColor: AppColors.backgroundSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.comment_rounded,
                          color: Color(comment.color).withOpacity(1.0)),
                      const SizedBox(width: 8),
                      Text(isNew ? "إضافة تعليق" : "التعليق",
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 16)),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: controller,
                          maxLines: 4,
                          enabled:
                              _isDrawingMode, // لا يمكن التعديل إذا كان القلم مغلقاً
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: _isDrawingMode
                                ? "اكتب ملاحظاتك هنا..."
                                : "لا يوجد نص...",
                            hintStyle:
                                TextStyle(color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.backgroundPrimary,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        if (_isDrawingMode) ...[
                          const SizedBox(height: 20),
                          // ✅ شريط التحكم في حجم التعليق
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                "حجم الأيقونة: ${(comment.scale).toStringAsFixed(1)}",
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ),
                          Slider(
                              value: comment.scale,
                              min: 0.5,
                              max: 4.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor:
                                  AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() => comment.scale = val);
                                setState(
                                    () {}); // تحديث الشاشة الرئيسية لرؤية التغيير فوراً
                              }),
                          const SizedBox(height: 10),
                          // ✅ شريط التحكم في الشفافية
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                "الشفافية: ${(Color(comment.color).opacity * 100).toInt()}%",
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ),
                          Slider(
                              value: Color(comment.color).opacity,
                              min: 0.1,
                              max: 1.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor:
                                  AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() {
                                  // تغيير قيمة الألفا للون وحفظه
                                  Color baseColor = Color(comment.color);
                                  comment.color =
                                      baseColor.withOpacity(val).value;
                                });
                                setState(
                                    () {}); // تحديث الشاشة الرئيسية لرؤية التغيير فوراً
                              }),
                        ]
                      ],
                    ),
                  ),
                  actions: [
                    if (!isNew &&
                        _isDrawingMode) // يظهر زر الحذف فقط في وضع القلم
                      TextButton(
                        onPressed: () {
                          setState(
                              () => _pageComments[pageNumber]?.remove(comment));
                          Navigator.pop(ctx);
                        },
                        child: const Text("حذف",
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(_isDrawingMode ? "إلغاء" : "إغلاق",
                          style: const TextStyle(color: Colors.grey)),
                    ),
                    if (_isDrawingMode) // يظهر زر الحفظ فقط في وضع التعديل
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentYellow,
                            foregroundColor: Colors.black),
                        onPressed: () {
                          setState(() {
                            comment.text = controller.text;
                            if (isNew && comment.text.trim().isNotEmpty) {
                              if (_pageComments[pageNumber] == null)
                                _pageComments[pageNumber] = [];
                              _pageComments[pageNumber]!.add(comment);
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("حفظ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ]);
            }));
  }

  // --- منطق الرسم ---

  void _startStroke(DragStartDetails details, BuildContext context,
      Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);
    setState(() {
      _activePage = page.pageNumber;
      double width = _selectedTool == 2
          ? _eraserSize
          : (_selectedTool == 1 ? _highlightSize : _penSize);
      _currentLine = DrawingLine(
        points: [relativePoint],
        color: _selectedTool == 2 ? 0 : _selectedColor.value,
        strokeWidth: width,
        isHighlighter: _selectedTool == 1,
        isEraser: _selectedTool == 2,
      );
    });
  }

  void _updateStroke(
      DragUpdateDetails details, BuildContext context, Rect pageRect) {
    if (!_isDrawingMode || _currentLine == null) return;
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);
    setState(() => _currentLine!.points.add(relativePoint));
  }

  void _endStroke(PdfPage page) {
    if (_currentLine != null) {
      setState(() {
        if (_pageDrawings[page.pageNumber] == null)
          _pageDrawings[page.pageNumber] = [];
        _pageDrawings[page.pageNumber]!.add(_currentLine!);
        _currentLine = null;
      });
    }
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(25),
          boxShadow: [const BoxShadow(color: Colors.black54, blurRadius: 10)]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _toolIcon(LucideIcons.penTool, 0),
                const SizedBox(width: 8),
                _toolIcon(LucideIcons.highlighter, 1),
                const SizedBox(width: 8),
                _toolIcon(LucideIcons.eraser, 2),
                const SizedBox(width: 8),
                _toolIcon(LucideIcons.messageSquare, 3),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(LucideIcons.undo,
                      color: Colors.white, size: 20),
                  onPressed: () {
                    if (_pageDrawings[_activePage]?.isNotEmpty ?? false) {
                      setState(() => _pageDrawings[_activePage]!.removeLast());
                    }
                  },
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: Colors.grey),
                const SizedBox(width: 12),
                if (_selectedTool != 2) ...[
                  _colorCircle(Colors.red),
                  _colorCircle(Colors.blue),
                  _colorCircle(Colors.green),
                  _colorCircle(Colors.yellow),
                  _colorCircle(Colors.white),
                ],
              ],
            ),
          ),
          if (_selectedTool != 3) const SizedBox(height: 8),
          if (_selectedTool != 3) _sizeSlider(),
        ],
      ),
    );
  }

  Widget _sizeSlider() {
    return Slider(
      value: _selectedTool == 2
          ? _eraserSize
          : (_selectedTool == 1 ? _highlightSize : _penSize),
      min: 0.001,
      max: 0.08,
      activeColor: _selectedTool == 2 ? Colors.white : _selectedColor,
      onChanged: (val) => setState(() {
        if (_selectedTool == 2)
          _eraserSize = val;
        else if (_selectedTool == 1)
          _highlightSize = val;
        else
          _penSize = val;
      }),
    );
  }

  Widget _toolIcon(IconData icon, int index) {
    return Container(
      decoration: BoxDecoration(
          color: _selectedTool == index
              ? AppColors.accentYellow.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8)),
      child: IconButton(
        icon: Icon(icon,
            color:
                _selectedTool == index ? AppColors.accentYellow : Colors.grey,
            size: 20),
        onPressed: () => setState(() => _selectedTool = index),
      ),
    );
  }

  Widget _colorCircle(Color color) {
    return GestureDetector(
      onTap: () => setState(() {
        _selectedColor = color;
        if (_selectedTool == 2) _selectedTool = 0;
      }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: _selectedColor == color
                ? Border.all(color: Colors.white, width: 2)
                : null),
      ),
    );
  }
}

class RelativeSketchPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final Size pageSize;

  RelativeSketchPainter({required this.lines, required this.pageSize});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (var line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = line.isHighlighter ? StrokeCap.butt : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.strokeWidth * pageSize.width;

      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else {
        paint.color =
            Color(line.color).withOpacity(line.isHighlighter ? 0.35 : 1.0);
        if (line.isHighlighter) paint.blendMode = BlendMode.darken;
      }

      if (line.points.length > 1) {
        final path = Path();
        path.moveTo(line.points[0].dx * pageSize.width,
            line.points[0].dy * pageSize.height);
        for (int i = 1; i < line.points.length; i++) {
          path.lineTo(line.points[i].dx * pageSize.width,
              line.points[i].dy * pageSize.height);
        }
        canvas.drawPath(path, paint);
      } else if (line.points.isNotEmpty) {
        var p = Offset(line.points[0].dx * pageSize.width,
            line.points[0].dy * pageSize.height);
        canvas.drawPoints(PointMode.points, [p], paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
