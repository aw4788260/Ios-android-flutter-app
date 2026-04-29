// ============================================================
// PdfPageMetaService — Feature 8: Reading Progress Visual Indicators
// Tracks: visited pages, pages with annotations, bookmarked pages.
// Hive box: pdf_page_meta
// Key: {pdfId}_visited  → Set<int> stored as List<int>
// ============================================================

import '../../services/storage_service.dart';

class PdfPageMetaService {
  static const String _boxName = 'pdf_page_meta';

  // ---- Visited Pages ----------------------------------------

  static Future<Set<int>> loadVisitedPages(String pdfId) async {
    try {
      final box = await StorageService.openBox(_boxName);
      final raw = box.get('${pdfId}_visited');
      if (raw == null) return {};
      return Set<int>.from((raw as List<dynamic>).map((e) => e as int));
    } catch (_) {
      return {};
    }
  }

  static Future<void> markPageVisited(
      String pdfId, int pageNumber, Set<int> visited) async {
    try {
      visited.add(pageNumber);
      final box = await StorageService.openBox(_boxName);
      await box.put('${pdfId}_visited', visited.toList());
    } catch (_) {}
  }
}
