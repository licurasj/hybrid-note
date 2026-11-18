import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'frame_overlap.dart';

// The page's query string, with its leading '?' (or empty).
String pageQuery() {
  final JSObject? location = globalContext['location'] as JSObject?;
  final JSString? search = location?['search'] as JSString?;
  return search?.toDart ?? '';
}

// True when the main pointer is coarse: a phone or tablet touch screen.
bool coarsePointer() {
  if (!globalContext.has('matchMedia')) {
    return false;
  }
  final JSObject query = globalContext.callMethod<JSObject>(
    'matchMedia'.toJS,
    '(pointer: coarse)'.toJS,
  );
  final JSBoolean? matches = query['matches'] as JSBoolean?;
  return matches?.toDart ?? false;
}

// How much of this frame the parent page's on-screen keyboard covers, kept
// current from the parent's visualViewport (resize and scroll) and this
// window's resize (frameBottomOverlap). Null when the demo is not in a
// frame, the parent is on another origin (any access throws or the frame
// element is hidden) or the parent has no visualViewport: then the demo
// keeps its own keyboard handling only.
ValueListenable<double>? frameKeyboardInset() {
  final JSObject viewport;
  final JSObject frame;
  try {
    final JSObject? maybeParent = globalContext['parent'] as JSObject?;
    if (maybeParent == null || maybeParent.strictEquals(globalContext).toDart) {
      return null;
    }
    final JSObject? maybeFrame = globalContext['frameElement'] as JSObject?;
    final JSObject? maybeViewport = maybeParent['visualViewport'] as JSObject?;
    if (maybeFrame == null || maybeViewport == null) {
      return null;
    }
    viewport = maybeViewport;
    frame = maybeFrame;
  } catch (_) {
    return null;
  }

  double read() {
    try {
      final JSObject rect = frame.callMethod<JSObject>(
        'getBoundingClientRect'.toJS,
      );
      return frameBottomOverlap(
        frameBottom: (rect['bottom'] as JSNumber).toDartDouble,
        viewportTop: (viewport['offsetTop'] as JSNumber).toDartDouble,
        viewportHeight: (viewport['height'] as JSNumber).toDartDouble,
      );
    } catch (_) {
      return 0;
    }
  }

  final ValueNotifier<double> inset = ValueNotifier<double>(read());
  final JSFunction update = ((JSAny? _) {
    inset.value = read();
  }).toJS;
  try {
    viewport.callMethod<JSAny?>('addEventListener'.toJS, 'resize'.toJS, update);
    viewport.callMethod<JSAny?>('addEventListener'.toJS, 'scroll'.toJS, update);
    globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'resize'.toJS,
      update,
    );
  } catch (_) {
    return null;
  }
  // The listeners stay for the page's lifetime: the demo runs until the
  // frame goes.
  return inset;
}
