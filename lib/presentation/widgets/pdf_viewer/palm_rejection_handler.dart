// ============================================================
// PalmRejectionHandler — Feature 6: Palm Rejection / Input Filtering
//
// Wraps child with a Listener that tracks active pointer IDs.
// Rules:
//  - If drawing mode is active, only the FIRST pointer that began a
//    stroke is honoured; subsequent pointers (palm) are silently ignored.
//  - If stylus kind is detected (PointerDeviceKind.stylus / invertedStylus),
//    only stylus input is forwarded to the drawing layer.
//  - When stylus is in use, finger touches are treated as navigation
//    (pass-through), preventing accidental strokes.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class PalmRejectionHandler extends StatefulWidget {
  final Widget child;

  /// True when the annotation drawing mode is active.
  final bool isDrawingMode;

  /// Called with a normalised position [0..1] on stroke start.
  final void Function(Offset localPos)? onDrawStart;

  /// Called with delta position on stroke update.
  final void Function(Offset localPos)? onDrawUpdate;

  /// Called on stroke end.
  final VoidCallback? onDrawEnd;

  /// Called for a tap (for comment placement).
  final void Function(Offset localPos)? onTap;

  const PalmRejectionHandler({
    super.key,
    required this.child,
    required this.isDrawingMode,
    this.onDrawStart,
    this.onDrawUpdate,
    this.onDrawEnd,
    this.onTap,
  });

  @override
  State<PalmRejectionHandler> createState() => _PalmRejectionHandlerState();
}

class _PalmRejectionHandlerState extends State<PalmRejectionHandler> {
  /// The pointer ID that "owns" the current drawing stroke, null if idle.
  int? _activePointerId;

  /// Whether the active stroke was initiated by a stylus.
  bool _activeStylusMode = false;

  /// True once any stylus pointer has been seen in the session.
  bool _stylusDetected = false;

  bool _isStylusKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.isDrawingMode) return;

    final isStylusInput = _isStylusKind(event.kind);

    // Detect stylus presence for session.
    if (isStylusInput) _stylusDetected = true;

    // If stylus has been detected, only allow stylus strokes.
    if (_stylusDetected && !isStylusInput) {
      // Finger in stylus session → treat as navigation, skip.
      return;
    }

    // Only one active pointer allowed for drawing (palm rejection).
    if (_activePointerId != null) return;

    _activePointerId = event.pointer;
    _activeStylusMode = isStylusInput;
    widget.onDrawStart?.call(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.isDrawingMode) return;
    if (event.pointer != _activePointerId) return;
    widget.onDrawUpdate?.call(event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.isDrawingMode) return;
    if (event.pointer != _activePointerId) return;
    _activePointerId = null;
    _activeStylusMode = false;
    widget.onDrawEnd?.call();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointerId) {
      _activePointerId = null;
      _activeStylusMode = false;
      widget.onDrawEnd?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
