import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hybrid_note/home_cards_view.dart';

// Home's blobs move for ever, which pumpAndSettle would wait on. The tests of
// the blob itself turn this off again; it is set back before every test, so one
// that fails before its tearDown does not leave blobs moving for the next.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HomeBlob.stillForTests = true;
  setUp(() => HomeBlob.stillForTests = true);
  await testMain();
}
