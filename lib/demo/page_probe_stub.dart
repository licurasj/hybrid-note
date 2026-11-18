import 'package:flutter/foundation.dart';

// Not on web: no page URL and no touch frame.
String pageQuery() => '';

bool coarsePointer() => false;

// Not on web: no parent page, so no keyboard from outside the frame.
ValueListenable<double>? frameKeyboardInset() => null;
