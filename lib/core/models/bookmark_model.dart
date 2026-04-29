// ============================================================
// BookmarkModel — Feature 2: Bookmark System
// Stored in Hive box: pdf_bookmarks
// Key format: {pdfId}_{pageNumber}
// ============================================================

class BookmarkModel {
  final String id;
  final String pdfId;
  final int pageNumber;
  final String? label;
  final DateTime createdAt;

  BookmarkModel({
    required this.id,
    required this.pdfId,
    required this.pageNumber,
    this.label,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pdfId': pdfId,
      'pg': pageNumber,
      'label': label,
      'ca': createdAt.millisecondsSinceEpoch,
    };
  }

  factory BookmarkModel.fromJson(Map<String, dynamic> json) {
    return BookmarkModel(
      id: json['id'] as String,
      pdfId: json['pdfId'] as String,
      pageNumber: (json['pg'] as num).toInt(),
      label: json['label'] as String?,
      createdAt: json['ca'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['ca'] as int)
          : DateTime.now(),
    );
  }

  /// Hive storage key for this bookmark.
  String get hiveKey => '${pdfId}_$pageNumber';
}
