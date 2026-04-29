// ============================================================
// PdfBookmarkService — Feature 2: Bookmark System
// Hive box: pdf_bookmarks
// ============================================================

import '../../services/storage_service.dart';
import '../../models/bookmark_model.dart';

class PdfBookmarkService {
  static const String _boxName = 'pdf_bookmarks';

  /// Load all bookmarks for [pdfId].
  static Future<List<BookmarkModel>> loadBookmarks(String pdfId) async {
    try {
      final box = await StorageService.openBox(_boxName);
      final keys =
          box.keys.where((k) => (k as String).startsWith('${pdfId}_'));
      final result = <BookmarkModel>[];
      for (final key in keys) {
        final raw = box.get(key);
        if (raw != null) {
          result.add(
              BookmarkModel.fromJson(Map<String, dynamic>.from(raw as Map)));
        }
      }
      result.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Returns true if [pageNumber] is bookmarked for [pdfId].
  static Future<bool> isBookmarked(String pdfId, int pageNumber) async {
    try {
      final box = await StorageService.openBox(_boxName);
      return box.containsKey('${pdfId}_$pageNumber');
    } catch (_) {
      return false;
    }
  }

  /// Add bookmark. Returns the new [BookmarkModel].
  static Future<BookmarkModel> addBookmark(
      String pdfId, int pageNumber, {String? label}) async {
    final bm = BookmarkModel(
      id: '${pdfId}_${pageNumber}_${DateTime.now().millisecondsSinceEpoch}',
      pdfId: pdfId,
      pageNumber: pageNumber,
      label: label,
    );
    final box = await StorageService.openBox(_boxName);
    await box.put(bm.hiveKey, bm.toJson());
    return bm;
  }

  /// Remove bookmark for [pageNumber].
  static Future<void> removeBookmark(String pdfId, int pageNumber) async {
    try {
      final box = await StorageService.openBox(_boxName);
      await box.delete('${pdfId}_$pageNumber');
    } catch (_) {}
  }
}
