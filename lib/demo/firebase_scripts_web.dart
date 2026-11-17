import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Read by firebase_core_web when Firebase.initializeApp injects the bundles,
// so it must be set before the first initializeApp.
void skipFirebaseScripts(List<String> services) {
  globalContext['flutterfire_ignore_scripts'] = [
    for (final String service in services) service.toJS,
  ].toJS;
}
