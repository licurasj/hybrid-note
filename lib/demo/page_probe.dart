// What the demo reads from its web page at start (T-18 PX-3, Q-145): the
// page URL's query and whether the main pointer is coarse (touch); and,
// inside a same-origin parent page, how much of the frame the parent's
// on-screen keyboard covers (T-18 unit 5, Q-147).
// Elsewhere the query is empty, the pointer fine and there is no parent.
export 'page_probe_stub.dart'
    if (dart.library.js_interop) 'page_probe_web.dart';
