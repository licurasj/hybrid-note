import 'dart:typed_data';
import 'dart:ui' as ui;

// A ring's large icon (T-13 unit 9, owner's pick): the app logo's mark (the
// owner's H on a note with a pen, assets/app_icon.png, the launcher icon's
// source) in the list's colour on a clear ground, so the shade's own
// background shows around it and through the H, as with the small icon.
// PNG bytes, kept per colour.
class RingLogo {
  RingLogo._();

  static const String asset = 'assets/app_icon.png';

  // Pixels per side: Android shows large icons at 48 dp, so this is sharp up
  // to 4x screens.
  static const int size = 192;

  // The logo's ground (AppColors.appBlue) and mark (white), by red channel.
  static const int _groundRed = 0x70;

  static final Map<int, Future<Uint8List>> _cache = {};

  // [color] is ARGB.
  static Future<Uint8List> png(int color) =>
      _cache[color] ??= _draw(color).catchError((Object error) {
        _cache.remove(color);
        throw error;
      });

  static Future<Uint8List> _draw(int color) async {
    final Uint8List logo = await _logoPixels();
    final int r = (color >> 16) & 0xFF;
    final int g = (color >> 8) & 0xFF;
    final int b = color & 0xFF;
    final Uint8List out = Uint8List(size * size * 4);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final int i = (y * size + x) * 4;
        // How white the logo is here: 0 on the blue ground, 1 on the mark.
        final double white = ((logo[i] - _groundRed) / (0xFF - _groundRed))
            .clamp(0.0, 1.0);
        out[i] = r;
        out[i + 1] = g;
        out[i + 2] = b;
        out[i + 3] = (white * 0xFF).round();
      }
    }
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      out,
    );
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: size,
      height: size,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.Image image = (await codec.getNextFrame()).image;
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Ring logo not drawn');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  // The logo at [size], as straight RGBA. Read through dart:ui, so it works
  // in the background check's isolate too.
  static Future<Uint8List> _logoPixels() async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromAsset(asset);
    final ui.Codec codec = await ui.instantiateImageCodecFromBuffer(
      buffer,
      targetWidth: size,
      targetHeight: size,
    );
    final ui.Image image = (await codec.getNextFrame()).image;
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) {
        throw StateError('Logo not read');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}
