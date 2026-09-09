import 'package:flutter/services.dart' show appFlavor;
import 'package:test/test.dart';

import 'package:inclinometer/config/build_flavor.dart';

void main() {
  // The test host is built with no --flavor, so appFlavor is null and the
  // build is treated as the `github` (self-update-enabled) channel.
  test('no flavor ⇒ github channel, self-update enabled', () {
    expect(appFlavor, isNull);
    expect(kIsPlayBuild, isFalse);
    expect(kSelfUpdateEnabled, isTrue);
  });

  test('kSelfUpdateEnabled is the negation of kIsPlayBuild', () {
    expect(kSelfUpdateEnabled, equals(!kIsPlayBuild));
  });
}
