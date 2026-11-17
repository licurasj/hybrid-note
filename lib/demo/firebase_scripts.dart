// Firebase JS bundles the demo does not load (T-18 unit 2b). On web,
// Firebase.initializeApp injects the bundle of every registered plugin from
// gstatic, Firestore's included, unless the page lists it in
// `window.flutterfire_ignore_scripts`. Elsewhere this does nothing.
export 'firebase_scripts_stub.dart'
    if (dart.library.js_interop) 'firebase_scripts_web.dart';
