// Reloads the web page; does nothing elsewhere. After sign-out on web the
// cleared Firestore instance cannot be used again until the page reloads
// (FirestoreSetup.reloadAfterClear).
export 'page_reload_stub.dart' if (dart.library.js_interop) 'page_reload_web.dart';
