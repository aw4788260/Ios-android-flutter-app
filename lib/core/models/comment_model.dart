// ============================================================
// CommentModel — Updated with optional tag field
// Backward compatible: old stored comments load fine (tag = null)
// ============================================================

/// Tags that can be attached to a comment.
enum CommentTag {
  important,
  question,
  exam,
  revise,
}

/// Human-readable label for each tag (Arabic UI).
extension CommentTagLabel on CommentTag {
  String get label {
    switch (this) {
      case CommentTag.important:
        return 'مهم';
      case CommentTag.question:
        return 'سؤال';
      case CommentTag.exam:
        return 'امتحان';
      case CommentTag.revise:
        return 'مراجعة';
    }
  }

  /// Tag accent color used in chips and filter UI.
  int get colorValue {
    switch (this) {
      case CommentTag.important:
        return 0xFFEF4444; // red
      case CommentTag.question:
        return 0xFF3B82F6; // blue
      case CommentTag.exam:
        return 0xFFdba91d; // gold
      case CommentTag.revise:
        return 0xFF22C55E; // green
    }
  }

  /// Serialised string stored in Hive.
  String get key => name; // uses enum name, e.g. 'important'

  static CommentTag? fromKey(String? key) {
    if (key == null) return null;
    try {
      return CommentTag.values.firstWhere((t) => t.name == key);
    } catch (_) {
      return null;
    }
  }
}

class CommentModel {
  final String id;
  String text;
  double dx;
  double dy;
  int color;
  double scale;

  /// Optional tag — null means no tag (backward compatible with stored data).
  CommentTag? tag;

  /// Page number — stored so NotesSummaryPanel can aggregate without per-page look-up.
  int pageNumber;

  /// Creation timestamp for sort-by-newest.
  final DateTime createdAt;

  CommentModel({
    required this.id,
    required this.text,
    required this.dx,
    required this.dy,
    required this.color,
    required this.pageNumber,
    this.scale = 1.0,
    this.tag,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'dx': dx,
      'dy': dy,
      'c': color,
      's': scale,
      'pg': pageNumber,
      'tag': tag?.key,
      'ca': createdAt.millisecondsSinceEpoch,
    };
  }

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] as String,
      text: json['text'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      color: json['c'] as int,
      scale: (json['s'] as num?)?.toDouble() ?? 1.0,
      // Safe migration: missing 'pg' defaults to 0 (will be set by caller on load).
      pageNumber: (json['pg'] as num?)?.toInt() ?? 0,
      tag: CommentTagLabel.fromKey(json['tag'] as String?),
      createdAt: json['ca'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['ca'] as int)
          : DateTime.now(),
    );
  }
}
