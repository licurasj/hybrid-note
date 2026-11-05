import 'dart:async';

import 'package:hybrid_note/home_cards_view.dart';

// Home's blobs move for ever, which pumpAndSettle would wait on. The test of
// the blob itself turns this off again.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HomeBlob.stillForTests = true;
  await testMain();
}
