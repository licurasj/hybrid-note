import 'dart:typed_data';
import 'dart:ui' as ui;

// A ring's large icon (T-13 unit 9, Proposed): a flat, solid disc in the
// list's colour on a clear ground, like the blob on the list's home card. Drawn
// in code, so any list colour has one; PNG bytes, kept per colour.
class RingDot {
  RingDot._();

  // Pixels per side: Android shows large icons at 48 dp, so this is sharp up
  // to about 2.7x screens and stays a few hundred bytes.
  static const int size = 128;

  static final Map<int, Future<Uint8List>> _cache = {};

  // [color] is ARGB.
  static Future<Uint8List> png(int color) =>
      _cache[color] ??= _draw(color).catchError((Object error) {
        _cache.remove(color);
        throw error;
      });

  static Future<Uint8List> _draw(int color) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final double half = size / 2;
    ui.Canvas(recorder).drawCircle(
      ui.Offset(half, half),
      half,
      ui.Paint()
        ..isAntiAlias = true
        ..color = ui.Color(color),
    );
    final ui.Image image = await recorder.endRecording().toImage(size, size);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Ring dot not drawn');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
