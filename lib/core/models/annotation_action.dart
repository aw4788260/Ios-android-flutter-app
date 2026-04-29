// ============================================================
// AnnotationAction — Feature 5: Multi-level Undo / Redo
// Describes a reversible user action in the PDF viewer.
// ============================================================

import 'drawing_model.dart';
import 'comment_model.dart';

enum AnnotationActionType {
  addStroke,
  eraseStroke,
  addComment,
  deleteComment,
  moveComment,
}

class AnnotationAction {
  final AnnotationActionType type;
  final int pageNumber;

  // --- Drawing stroke actions ---
  final DrawingLine? stroke;
  final int? strokeIndex; // index inside _pageDrawings[pageNumber]

  // --- Comment actions ---
  final CommentModel? comment;

  // --- Move comment action ---
  final double? prevDx;
  final double? prevDy;
  final double? nextDx;
  final double? nextDy;

  const AnnotationAction._({
    required this.type,
    required this.pageNumber,
    this.stroke,
    this.strokeIndex,
    this.comment,
    this.prevDx,
    this.prevDy,
    this.nextDx,
    this.nextDy,
  });

  factory AnnotationAction.addStroke(int page, DrawingLine stroke) {
    return AnnotationAction._(
      type: AnnotationActionType.addStroke,
      pageNumber: page,
      stroke: stroke,
    );
  }

  factory AnnotationAction.eraseStroke(
      int page, DrawingLine stroke, int index) {
    return AnnotationAction._(
      type: AnnotationActionType.eraseStroke,
      pageNumber: page,
      stroke: stroke,
      strokeIndex: index,
    );
  }

  factory AnnotationAction.addComment(int page, CommentModel comment) {
    return AnnotationAction._(
      type: AnnotationActionType.addComment,
      pageNumber: page,
      comment: comment,
    );
  }

  factory AnnotationAction.deleteComment(int page, CommentModel comment) {
    return AnnotationAction._(
      type: AnnotationActionType.deleteComment,
      pageNumber: page,
      comment: comment,
    );
  }

  factory AnnotationAction.moveComment(
    int page,
    CommentModel comment,
    double prevDx,
    double prevDy,
    double nextDx,
    double nextDy,
  ) {
    return AnnotationAction._(
      type: AnnotationActionType.moveComment,
      pageNumber: page,
      comment: comment,
      prevDx: prevDx,
      prevDy: prevDy,
      nextDx: nextDx,
      nextDy: nextDy,
    );
  }
}
