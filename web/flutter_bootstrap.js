{{flutter_js}}
{{flutter_build_config}}

// No service worker (T-18 unit 2b): Flutter's default bootstrap registers
// flutter_service_worker.js, a deprecated worker that only unregisters
// itself and reloads the page. The portfolio embeds the demo with no service
// worker, and the real web build has no offline start (Q-85), so neither
// build registers one.
_flutter.loader.load();
