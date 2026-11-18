import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
