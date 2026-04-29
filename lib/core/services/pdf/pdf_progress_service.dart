// ============================================================
// PdfProgressService — Feature 1: Auto Resume Last Reading Position
// Hive box: pdf_reader_progress
// Key format: progress_{pdfId}
// ============================================================

import '../../services/storage_service.dart';

class PdfProgressService {
  static const String _boxName = 'pdf_reader_progress';

  /// Load last saved page for [pdfId]. Returns 1 if no saved progress.
  static Future<int> loadLastPosition(String pdfId) async {
    try {
      final box = await StorageService.openBox(_boxName);
      final data = box.get('progress_$pdfId');
      if (data == null) return 1;
      final page = (data['page'] as num?)?.toInt() ?? 1;
      return page < 1 ? 1 : page;
    } catch (e) {
      return 1;
    }
  }

  /// Persist current [pageNumber] for [pdfId].
  static Future<void> saveLastPosition(String pdfId, int pageNumber) async {
    try {
      final box = await StorageService.openBox(_boxName);
      await box.put('progress_$pdfId', {
        'page': pageNumber,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }
}
