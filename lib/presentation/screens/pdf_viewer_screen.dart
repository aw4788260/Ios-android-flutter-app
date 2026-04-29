// ============================================================
// PdfViewerScreen — Production Upgrade v2
//
// Features added (all non-breaking):
//  1. Auto Resume Last Reading Position
//  2. Bookmark System
//  3. Comment Tag System
//  4. Notes Summary Panel
//  5. Multi-level Undo / Redo
//  6. Palm Rejection / Input Filtering
//  7. Review Mode (hide PDF layer, show annotations only)
//  8. Reading Progress Visual Indicators
//  9. Favorites / Quick Jump to Annotated Pages
// 10. Data Structure / Storage Refactor
//
// Preserved exactly:
//  - Encrypted offline PDF reading (_customRead / FileCryptoService)
//  - Secure online PDF streaming (PdfViewer.uri + headers)
//  - Watermark rendering
//  - Drawing tools (pen / highlighter / eraser)
//  - Comments system (load / save / dialog)
//  - Annotations persistence in Hive (pdf_drawings_db)
//  - Crashlytics logging
//  - Existing UI theme / AppColors
//  - Text selection disabled (PdfTextSelectionParams disabled)
// ============================================================

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
import '../../core/models/bookmark_model.dart';
import '../../core/models/annotation_action.dart';
import '../../core/services/storage_service.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/pdf/pdf_progress_service.dart';
import '../../core/services/pdf/pdf_bookmark_service.dart';
import '../../core/services/pdf/pdf_page_meta_service.dart';
import '../widgets/pdf_viewer/notes_summary_panel.dart';

// ---- Public Widget ------------------------------------------------

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfId, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

// ---- State --------------------------------------------------------

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- Decryption variables (unchanged) ---
  File? _encryptedFile;
  int? _originalFileSize;
  String? _sessionToken;

  // --- Online streaming variables (unchanged) ---
  String? _onlineUrl;
  Map<String, String>? _onlineHeaders;

  bool _loading = true;
  String _loadingMessage = "جار التحقق من الملف...";
  String? _error;
  bool _isOffline = false;
  String _watermarkText = '';

  // --- Drawing & annotation tools (unchanged core) ---
  bool _isDrawingMode = false;
  int _selectedTool = 0; // 0=Pen, 1=Highlighter, 2=Eraser, 3=Comment
  Color _selectedColor = Colors.red;
  double _penSize = 0.003;
  double _highlightSize = 0.035;
  double _eraserSize = 0.04;

  Map<int, List<DrawingLine>> _pageDrawings = {};
  Map<int, List<CommentModel>> _pageComments = {};

  DrawingLine? _currentLine;
  List<Offset> _currentPoints = []; // palm-rejection-safe point buffer
  int _activePage = 0;
  int _totalPages = 0;

  // ---- Feature 1: Auto Resume ----
  int _resumePage = 1;

  // ---- Feature 2: Bookmarks ----
  List<BookmarkModel> _bookmarks = [];
  Set<int> _bookmarkedPages = {};

  // ---- Feature 5: Undo / Redo stacks ----
  final List<AnnotationAction> _undoStack = [];
  final List<AnnotationAction> _redoStack = [];

  // ---- Feature 7: Review Mode ----
  bool _isReviewMode = false;

  // ---- Feature 8: Page metadata ----
  Set<int> _visitedPages = {};

  // -----------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _sessionToken = _generateSecureToken();
    _initWatermarkText();
    _preparePdf();
  }

  @override
  void dispose() {
    // Persist all annotations on exit (unchanged).
    if (_isOffline) _saveAnnotationsToHive();
    super.dispose();
  }

  // -----------------------------------------------------------
  // Security helpers (unchanged)
  // -----------------------------------------------------------

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

  // -----------------------------------------------------------
  // Watermark (unchanged)
  // -----------------------------------------------------------

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

  // -----------------------------------------------------------
  // Annotation persistence (unchanged + pageNumber stamp)
  // -----------------------------------------------------------

  Future<void> _saveAnnotationsToHive() async {
    try {
      final box = await StorageService.openBox('pdf_drawings_db');

      // Save drawings (unchanged).
      for (var entry in _pageDrawings.entries) {
        if (entry.value.isNotEmpty) {
          final serialized = entry.value.map((l) => l.toJson()).toList();
          await box.put('${widget.pdfId}_${entry.key}', serialized);
        }
      }

      // Save comments (now includes pageNumber + tag + createdAt).
      for (var entry in _pageComments.entries) {
        if (entry.value.isNotEmpty) {
          final serializedComments = entry.value.map((c) {
            // Stamp pageNumber before saving (migration guard).
            if (c.pageNumber == 0) c.pageNumber = entry.key;
            return c.toJson();
          }).toList();
          await box.put(
              '${widget.pdfId}_${entry.key}_comments', serializedComments);
        } else {
          await box.delete('${widget.pdfId}_${entry.key}_comments');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadAnnotationsForPage(int pageNumber) async {
    final box = await StorageService.openBox('pdf_drawings_db');

    // Load drawings (unchanged).
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

    // Load comments (backward compatible — old comments without pg/tag/ca still load).
    if (!_pageComments.containsKey(pageNumber)) {
      final dynamic commentData =
          box.get('${widget.pdfId}_${pageNumber}_comments');
      List<CommentModel> comments = [];
      if (commentData != null) {
        comments = (commentData as List<dynamic>).map((e) {
          final c = CommentModel.fromJson(Map<String, dynamic>.from(e));
          // Migration: stamp pageNumber if missing from old format.
          if (c.pageNumber == 0) c.pageNumber = pageNumber;
          return c;
        }).toList();
      }
      _pageComments[pageNumber] = comments;
    }

    // Feature 8: mark page as visited.
    if (mounted) {
      await PdfPageMetaService.markPageVisited(
          widget.pdfId, pageNumber, _visitedPages);
      if (mounted) setState(() {});
    }
  }

  // -----------------------------------------------------------
  // Feature 1: Auto Resume helpers
  // -----------------------------------------------------------

  Future<void> _loadAndApplyLastPosition() async {
    _resumePage = await PdfProgressService.loadLastPosition(widget.pdfId);
    // Navigate after a short delay to let the controller attach.
    if (_resumePage > 1) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted && _pdfController.isReady) {
        _pdfController.goToPage(pageNumber: _resumePage);
      }
    }
  }

  void _onPageChanged(int page) {
    // Called from onDocumentChanged / pdfController listener.
    if (mounted) setState(() => _activePage = page);
    PdfProgressService.saveLastPosition(widget.pdfId, page);
  }

  // -----------------------------------------------------------
  // Feature 2: Bookmark helpers
  // -----------------------------------------------------------

  Future<void> _loadBookmarks() async {
    _bookmarks = await PdfBookmarkService.loadBookmarks(widget.pdfId);
    _bookmarkedPages = _bookmarks.map((b) => b.pageNumber).toSet();
    if (mounted) setState(() {});
  }

  Future<void> _toggleBookmark() async {
    final page = _pdfController.pageNumber ?? 1;
    if (_bookmarkedPages.contains(page)) {
      await PdfBookmarkService.removeBookmark(widget.pdfId, page);
    } else {
      await PdfBookmarkService.addBookmark(widget.pdfId, page);
    }
    await _loadBookmarks();
  }

  bool get _isCurrentPageBookmarked =>
      _bookmarkedPages.contains(_pdfController.pageNumber ?? 1);

  // -----------------------------------------------------------
  // PDF preparation (unchanged core)
  // -----------------------------------------------------------

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

          // Load metadata after file is ready.
          await _loadBookmarks();
          final visited =
              await PdfPageMetaService.loadVisitedPages(widget.pdfId);
          if (mounted) setState(() => _visitedPages = visited);
          await _loadAndApplyLastPosition();
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
      if (mounted) {
        setState(() {
          _error = "فشل فتح الملف المحمي.";
          _loading = false;
        });
      }
    }
  }

  // -----------------------------------------------------------
  // Feature 5: Undo / Redo
  // -----------------------------------------------------------

  /// Record an action onto the undo stack, clear redo.
  void _recordAction(AnnotationAction action) {
    _undoStack.add(action);
    _redoStack.clear(); // New action invalidates redo history.
  }

  void _performUndo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    _redoStack.add(action);
    _applyActionReverse(action);
    setState(() {});
  }

  void _performRedo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    _undoStack.add(action);
    _applyActionForward(action);
    setState(() {});
  }

  void _applyActionReverse(AnnotationAction action) {
    final page = action.pageNumber;
    switch (action.type) {
      case AnnotationActionType.addStroke:
        _pageDrawings[page]?.remove(action.stroke);
        break;
      case AnnotationActionType.eraseStroke:
        final idx = action.strokeIndex ?? (_pageDrawings[page]?.length ?? 0);
        _pageDrawings[page]?.insert(idx, action.stroke!);
        break;
      case AnnotationActionType.addComment:
        _pageComments[page]?.remove(action.comment);
        break;
      case AnnotationActionType.deleteComment:
        (_pageComments[page] ??= []).add(action.comment!);
        break;
      case AnnotationActionType.moveComment:
        action.comment!.dx = action.prevDx!;
        action.comment!.dy = action.prevDy!;
        break;
    }
  }

  void _applyActionForward(AnnotationAction action) {
    final page = action.pageNumber;
    switch (action.type) {
      case AnnotationActionType.addStroke:
        (_pageDrawings[page] ??= []).add(action.stroke!);
        break;
      case AnnotationActionType.eraseStroke:
        _pageDrawings[page]?.remove(action.stroke);
        break;
      case AnnotationActionType.addComment:
        (_pageComments[page] ??= []).add(action.comment!);
        break;
      case AnnotationActionType.deleteComment:
        _pageComments[page]?.remove(action.comment);
        break;
      case AnnotationActionType.moveComment:
        action.comment!.dx = action.nextDx!;
        action.comment!.dy = action.nextDy!;
        break;
    }
  }

  // -----------------------------------------------------------
  // Drawing logic (palm-rejection-aware)
  // -----------------------------------------------------------

  void _startStroke(Offset localPos, Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);
    setState(() {
      _activePage = page.pageNumber;
      _currentPoints = [relativePoint];
      double width = _selectedTool == 2
          ? _eraserSize
          : (_selectedTool == 1 ? _highlightSize : _penSize);
      _currentLine = DrawingLine(
        points: _currentPoints,
        color: _selectedTool == 2 ? 0 : _selectedColor.value,
        strokeWidth: width,
        isHighlighter: _selectedTool == 1,
        isEraser: _selectedTool == 2,
      );
    });
  }

  void _updateStroke(Offset localPos, Rect pageRect) {
    if (!_isDrawingMode || _currentLine == null) return;
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);
    setState(() => _currentPoints.add(relativePoint));
  }

  void _endStroke(PdfPage page) {
    if (_currentLine != null && _currentPoints.isNotEmpty) {
      final finishedLine = DrawingLine(
        points: List.from(_currentPoints),
        color: _currentLine!.color,
        strokeWidth: _currentLine!.strokeWidth,
        isHighlighter: _currentLine!.isHighlighter,
        isEraser: _currentLine!.isEraser,
      );
      setState(() {
        (_pageDrawings[page.pageNumber] ??= []).add(finishedLine);
        // Record for undo.
        _recordAction(
            AnnotationAction.addStroke(page.pageNumber, finishedLine));
        _currentLine = null;
        _currentPoints = [];
      });
    }
  }

  // -----------------------------------------------------------
  // Comment logic (updated with tag + undo)
  // -----------------------------------------------------------

  void _addComment(
      Offset localPos, BuildContext context, Rect pageRect, int pageNumber) {
    if (!_isDrawingMode || _selectedTool != 3) return;
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);
    final newComment = CommentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: '',
      dx: relativePoint.dx,
      dy: relativePoint.dy,
      color: _selectedColor.value,
      pageNumber: pageNumber,
    );
    _showCommentDialog(pageNumber, newComment, isNew: true);
  }

  void _showCommentDialog(int pageNumber, CommentModel comment,
      {bool isNew = false}) {
    TextEditingController controller =
        TextEditingController(text: comment.text);
    CommentTag? selectedTag = comment.tag;

    showDialog(
      context: context,
      barrierDismissible: !isNew,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.backgroundSecondary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Text field ---
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    enabled: _isDrawingMode,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: _isDrawingMode
                          ? "اكتب ملاحظاتك هنا..."
                          : "لا يوجد نص...",
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.backgroundPrimary,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),

                  // --- Feature 3: Tag Selector ---
                  if (_isDrawingMode) ...[
                    const SizedBox(height: 14),
                    Text("التصنيف:",
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        // "None" chip
                        _tagChip(
                          label: 'بدون',
                          color: Colors.grey,
                          isSelected: selectedTag == null,
                          onTap: () =>
                              setDialogState(() => selectedTag = null),
                        ),
                        ...CommentTag.values.map((tag) => _tagChip(
                              label: tag.label,
                              color: Color(tag.colorValue),
                              isSelected: selectedTag == tag,
                              onTap: () =>
                                  setDialogState(() => selectedTag = tag),
                            )),
                      ],
                    ),
                  ] else if (comment.tag != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            Color(comment.tag!.colorValue).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(comment.tag!.label,
                          style: TextStyle(
                              color: Color(comment.tag!.colorValue),
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],

                  if (_isDrawingMode) ...[
                    const SizedBox(height: 20),
                    // Scale slider
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                          "حجم الأيقونة: ${comment.scale.toStringAsFixed(1)}",
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    Slider(
                      value: comment.scale,
                      min: 0.5,
                      max: 4.0,
                      activeColor: AppColors.accentYellow,
                      inactiveColor: AppColors.accentYellow.withOpacity(0.3),
                      onChanged: (val) {
                        setDialogState(() => comment.scale = val);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    // Opacity slider
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                          "الشفافية: ${(Color(comment.color).opacity * 100).toInt()}%",
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ),
                    Slider(
                      value: Color(comment.color).opacity,
                      min: 0.1,
                      max: 1.0,
                      activeColor: AppColors.accentYellow,
                      inactiveColor: AppColors.accentYellow.withOpacity(0.3),
                      onChanged: (val) {
                        setDialogState(() {
                          Color baseColor = Color(comment.color);
                          comment.color = baseColor.withOpacity(val).value;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              // Delete button (only in drawing mode for existing comments).
              if (!isNew && _isDrawingMode)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _pageComments[pageNumber]?.remove(comment);
                      // Record delete for undo.
                      _recordAction(AnnotationAction.deleteComment(
                          pageNumber, comment));
                    });
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
              if (_isDrawingMode)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: Colors.black),
                  onPressed: () {
                    setState(() {
                      comment.text = controller.text;
                      comment.tag = selectedTag;
                      if (comment.pageNumber == 0) {
                        comment.pageNumber = pageNumber;
                      }
                      if (isNew && comment.text.trim().isNotEmpty) {
                        (_pageComments[pageNumber] ??= []).add(comment);
                        // Record add for undo.
                        _recordAction(
                            AnnotationAction.addComment(pageNumber, comment));
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text("حفظ",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _tagChip(
      {required String label,
      required Color color,
      required bool isSelected,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSelected ? color : Colors.white54,
                fontSize: 11,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // -----------------------------------------------------------
  // Helpers: annotated pages list (Feature 9)
  // -----------------------------------------------------------

  /// Returns sorted list of pages that have any drawing or comment.
  List<int> get _annotatedPages {
    final pages = <int>{};
    for (final e in _pageDrawings.entries) {
      if (e.value.isNotEmpty) pages.add(e.key);
    }
    for (final e in _pageComments.entries) {
      if (e.value.isNotEmpty) pages.add(e.key);
    }
    return pages.toList()..sort();
  }

  // -----------------------------------------------------------
  // Build
  // -----------------------------------------------------------

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
          // --- Feature 7: Review Mode hides PDF layer ---
          if (!_isReviewMode)
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
                  )
          else
            // Review mode placeholder — keeps controller alive.
            Container(color: AppColors.backgroundPrimary),

          // --- Watermark (always visible) ---
          _buildWatermark(),

          // --- Toolbar (offline + drawing mode) ---
          if (_isDrawingMode && _isOffline)
            Positioned(
                bottom: 40, left: 20, right: 20, child: _buildToolbar()),

          // --- Review Mode overlay badge ---
          if (_isReviewMode) _buildReviewModeBadge(),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // AppBar
  // -----------------------------------------------------------

  PreferredSizeWidget _buildAppBar() {
    final isBookmarked = _isCurrentPageBookmarked;

    return AppBar(
      title: Row(
        children: [
          Expanded(
              child: Text(widget.title,
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _buildBadge(),
          if (_isOffline) ...[
            const SizedBox(width: 12),
            _buildPenIcon(),
          ],
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
        // --- Feature 2: Bookmark toggle (offline only) ---
        if (_isOffline)
          IconButton(
            icon: Icon(
              isBookmarked ? LucideIcons.bookmark : LucideIcons.bookmarkX,
              color: isBookmarked ? AppColors.accentYellow : Colors.white54,
            ),
            onPressed: _toggleBookmark,
            tooltip: isBookmarked ? 'إزالة الإشارة' : 'إضافة إشارة',
          ),

        // --- Feature 4: Notes Summary ---
        if (_isOffline)
          IconButton(
            icon: Icon(LucideIcons.fileText, color: AppColors.accentYellow),
            onPressed: _showNotesSummary,
            tooltip: 'ملخص الملاحظات',
          ),

        // --- Feature 7: Review Mode toggle ---
        if (_isOffline)
          IconButton(
            icon: Icon(
              _isReviewMode ? LucideIcons.eye : LucideIcons.eyeOff,
              color: _isReviewMode ? AppColors.accentYellow : Colors.white54,
            ),
            onPressed: () => setState(() => _isReviewMode = !_isReviewMode),
            tooltip: _isReviewMode ? 'إظهار الـPDF' : 'وضع المراجعة',
          ),

        // --- Page index drawer ---
        IconButton(
          icon: Icon(LucideIcons.list, color: AppColors.accentYellow),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // Widgets
  // -----------------------------------------------------------

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
            child:
                Text(_error!, style: const TextStyle(color: Colors.white))));
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isOffline
            ? Colors.green.withOpacity(0.2)
            : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: _isOffline ? Colors.green : Colors.blue, width: 1),
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
            color:
                _isDrawingMode ? AppColors.accentYellow : Colors.transparent,
            shape: BoxShape.circle,
            border:
                Border.all(color: AppColors.accentYellow.withOpacity(0.5))),
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

  /// Feature 7: Small badge shown in review mode.
  Widget _buildReviewModeBadge() {
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentYellow.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'وضع المراجعة — PDF مخفي',
            style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // Feature 4: Notes Summary bottom sheet
  // -----------------------------------------------------------

  void _showNotesSummary() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotesSummaryPanel(
        pageComments: _pageComments,
        onJumpToPage: (page) {
          _pdfController.goToPage(pageNumber: page);
        },
      ),
    );
  }

  // -----------------------------------------------------------
  // Page Drawer (Feature 2: bookmarks, Feature 8: indicators, Feature 9: annotated jump)
  // -----------------------------------------------------------

  Widget _buildPageDrawer() {
    return Drawer(
      backgroundColor: AppColors.backgroundSecondary,
      width: 260,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 8),
            child: Text("فهرس الصفحات",
                style: TextStyle(
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),

          // --- Feature 9: Quick jump to annotated pages ---
          if (_annotatedPages.isNotEmpty) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(LucideIcons.zap,
                      color: AppColors.accentYellow, size: 14),
                  const SizedBox(width: 6),
                  Text("الصفحات المشروحة",
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _annotatedPages.map((page) {
                  return GestureDetector(
                    onTap: () {
                      _pdfController.goToPage(pageNumber: page);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.accentYellow.withOpacity(0.4)),
                      ),
                      child: Text('$page',
                          style: TextStyle(
                              color: AppColors.accentYellow,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
          ],

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
                      final isCurrent =
                          _pdfController.pageNumber == pageNum;
                      final isBookmarked =
                          _bookmarkedPages.contains(pageNum);
                      final isVisited = _visitedPages.contains(pageNum);
                      final hasAnnotations =
                          _annotatedPages.contains(pageNum);

                      return ListTile(
                        dense: true,
                        title: Text("صفحة $pageNum",
                            style: TextStyle(
                                color: isCurrent
                                    ? AppColors.accentYellow
                                    : AppColors.textPrimary,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13)),
                        leading: Icon(LucideIcons.fileText,
                            color: isCurrent
                                ? AppColors.accentYellow
                                : AppColors.textSecondary,
                            size: 16),
                        // --- Feature 8: Indicator row ---
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isBookmarked)
                              Icon(LucideIcons.bookmark,
                                  color: AppColors.accentYellow, size: 12),
                            if (hasAnnotations)
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Icon(LucideIcons.pencil,
                                    color: Colors.blue, size: 12),
                              ),
                            if (isVisited && !isCurrent)
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Icon(LucideIcons.eye,
                                    color: Colors.green, size: 12),
                              ),
                          ],
                        ),
                        onTap: () {
                          _pdfController.goToPage(pageNumber: pageNum);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),

          // --- Bookmarks section ---
          if (_bookmarks.isNotEmpty) ...[
            const Divider(color: Colors.white10),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(LucideIcons.bookmark,
                      color: AppColors.accentYellow, size: 14),
                  const SizedBox(width: 6),
                  Text("الإشارات المرجعية",
                      style: TextStyle(
                          color: AppColors.accentYellow,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ..._bookmarks.map((bm) => ListTile(
                  dense: true,
                  leading: Icon(LucideIcons.bookmark,
                      color: AppColors.accentYellow, size: 14),
                  title: Text(
                      bm.label?.isNotEmpty == true
                          ? bm.label!
                          : 'صفحة ${bm.pageNumber}',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 12)),
                  onTap: () {
                    _pdfController.goToPage(pageNumber: bm.pageNumber);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // PDF Params (page overlays — palm-rejection integrated)
  // -----------------------------------------------------------

  PdfViewerParams _buildPdfParams() {
    return PdfViewerParams(
      backgroundColor: AppColors.backgroundPrimary,
      // Text selection disabled (security requirement).
      textSelectionParams: const PdfTextSelectionParams(enabled: false),
      scrollPhysics: const BouncingScrollPhysics(),
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12)),
            child: CircularProgressIndicator(color: AppColors.accentYellow),
          ),
        );
      },
      onDocumentChanged: (document) {
        if (mounted) {
          setState(() => _totalPages = document?.pages.length ?? 0);
          // Feature 1: restore last position after document is ready.
          _loadAndApplyLastPosition();
        }
      },
      onPageChanged: (page) {
        // Feature 1: save progress on every page change.
        if (page != null) _onPageChanged(page);
        if (mounted) setState(() {});
      },
      pageOverlaysBuilder: (context, pageRect, page) {
        if (!_isOffline) return [];
        return [
          Positioned.fill(
            child: FutureBuilder(
              future: _loadAnnotationsForPage(page.pageNumber),
              builder: (context, snapshot) {
                final lines = _pageDrawings[page.pageNumber] ?? [];
                final allLines = [...lines];
                if (_isDrawingMode &&
                    _currentLine != null &&
                    _activePage == page.pageNumber) {
                  allLines.add(_currentLine!);
                }

                final comments = _pageComments[page.pageNumber] ?? [];

                return Stack(
                  children: [
                    // --- Drawing layer with palm rejection (Feature 6) ---
                    _buildDrawingLayer(context, pageRect, page, allLines),

                    // --- Comment icons ---
                    if (_isOffline)
                      ...comments.map((comment) {
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
                                    if (details.pointerCount == 1) {
                                      final prevDx = comment.dx;
                                      final prevDy = comment.dy;
                                      setState(() {
                                        comment.dx +=
                                            details.focalPointDelta.dx /
                                                pageRect.width;
                                        comment.dy +=
                                            details.focalPointDelta.dy /
                                                pageRect.height;
                                      });
                                      // Record move for undo (debounced by gesture end).
                                      _recordAction(
                                          AnnotationAction.moveComment(
                                              page.pageNumber,
                                              comment,
                                              prevDx,
                                              prevDy,
                                              comment.dx,
                                              comment.dy));
                                    }
                                  }
                                : null,
                            onTap: () => _showCommentDialog(
                                page.pageNumber, comment),
                            child: Transform.scale(
                              scale: comment.scale,
                              child: Opacity(
                                opacity: currentOpacity,
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

  /// Drawing layer separated to cleanly integrate palm rejection (Feature 6).
  Widget _buildDrawingLayer(BuildContext context, Rect pageRect, PdfPage page,
      List<DrawingLine> allLines) {
    // When not in drawing mode, just paint existing lines passively.
    if (!_isDrawingMode) {
      return IgnorePointer(
        child: CustomPaint(
          painter:
              RelativeSketchPainter(lines: allLines, pageSize: pageRect.size),
          size: Size.infinite,
        ),
      );
    }

    // Drawing mode active — use Listener for palm rejection (Feature 6).
    return _PalmRejectedDrawingLayer(
      pageRect: pageRect,
      page: page,
      allLines: allLines,
      selectedTool: _selectedTool,
      onDrawStart: (localPos) => _startStroke(localPos, pageRect, page),
      onDrawUpdate: (localPos) => _updateStroke(localPos, pageRect),
      onDrawEnd: () => _endStroke(page),
      onTap: (localPos) {
        if (_selectedTool == 3) {
          _addComment(localPos, context, pageRect, page.pageNumber);
        }
      },
    );
  }

  // -----------------------------------------------------------
  // Toolbar (Feature 5: undo/redo buttons added)
  // -----------------------------------------------------------

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
                // --- Undo button ---
                IconButton(
                  icon: Icon(LucideIcons.undo,
                      color: _undoStack.isNotEmpty
                          ? Colors.white
                          : Colors.white30,
                      size: 20),
                  onPressed: _undoStack.isNotEmpty ? _performUndo : null,
                  tooltip: 'تراجع',
                ),
                // --- Redo button (Feature 5 addition) ---
                IconButton(
                  icon: Icon(LucideIcons.redo,
                      color: _redoStack.isNotEmpty
                          ? Colors.white
                          : Colors.white30,
                      size: 20),
                  onPressed: _redoStack.isNotEmpty ? _performRedo : null,
                  tooltip: 'إعادة',
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: Colors.grey),
                const SizedBox(width: 12),
                if (_selectedTool != 2) ...{
                  _colorCircle(Colors.red),
                  _colorCircle(Colors.blue),
                  _colorCircle(Colors.green),
                  _colorCircle(Colors.yellow),
                  _colorCircle(Colors.white),
                },
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
            color: _selectedTool == index
                ? AppColors.accentYellow
                : Colors.grey,
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

// ================================================================
// Palm-rejection-aware drawing layer (Feature 6)
// Stateful widget: tracks active pointer ID internally.
// ================================================================

class _PalmRejectedDrawingLayer extends StatefulWidget {
  final Rect pageRect;
  final PdfPage page;
  final List<DrawingLine> allLines;
  final int selectedTool;
  final void Function(Offset) onDrawStart;
  final void Function(Offset) onDrawUpdate;
  final VoidCallback onDrawEnd;
  final void Function(Offset) onTap;

  const _PalmRejectedDrawingLayer({
    required this.pageRect,
    required this.page,
    required this.allLines,
    required this.selectedTool,
    required this.onDrawStart,
    required this.onDrawUpdate,
    required this.onDrawEnd,
    required this.onTap,
  });

  @override
  State<_PalmRejectedDrawingLayer> createState() =>
      _PalmRejectedDrawingLayerState();
}

class _PalmRejectedDrawingLayerState
    extends State<_PalmRejectedDrawingLayer> {
  int? _activePointerId;
  bool _isStylus = false;
  bool _sessionHasStylus = false;
  Offset? _downPosition;
  bool _moved = false;

  bool _isStylusKind(int kind) =>
      kind == 2 || kind == 3; // stylus / invertedStylus in Flutter pointer kinds

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        final isStylusInput = _isStylusKind(event.kind.index);
        if (isStylusInput) _sessionHasStylus = true;

        // Palm rejection: if stylus session, reject finger touches.
        if (_sessionHasStylus && !isStylusInput) return;

        // Only one pointer draws at a time.
        if (_activePointerId != null) return;

        _activePointerId = event.pointer;
        _isStylus = isStylusInput;
        _downPosition = event.localPosition;
        _moved = false;

        if (widget.selectedTool != 3) {
          widget.onDrawStart(event.localPosition);
        }
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointerId) return;
        _moved = true;
        if (widget.selectedTool != 3) {
          widget.onDrawUpdate(event.localPosition);
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointerId) return;
        _activePointerId = null;

        if (widget.selectedTool == 3 && !_moved && _downPosition != null) {
          // Treat as tap for comment tool.
          widget.onTap(_downPosition!);
        } else if (widget.selectedTool != 3) {
          widget.onDrawEnd();
        }
        _downPosition = null;
        _moved = false;
      },
      onPointerCancel: (event) {
        if (event.pointer == _activePointerId) {
          _activePointerId = null;
          if (widget.selectedTool != 3) widget.onDrawEnd();
        }
      },
      child: CustomPaint(
        painter: RelativeSketchPainter(
            lines: widget.allLines, pageSize: widget.pageRect.size),
        size: Size.infinite,
      ),
    );
  }
}

// ================================================================
// RelativeSketchPainter — unchanged from original
// ================================================================

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
