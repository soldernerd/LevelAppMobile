// test/update_service_test.dart
// Unit tests for UpdateService — UPD-01, UPD-05.
// Covers _isNewer version comparison logic (integer-per-segment, not lexicographic).

import 'package:flutter_test/flutter_test.dart';
import 'package:inclinometer/services/update_service.dart';

void main() {
  group('UPD-01: Version comparison logic', () {
    test('UPD-01: returns true when remote patch is newer', () {
      expect(UpdateService.isNewerForTest('0.1.1', '0.1.0'), isTrue);
    });

    test('UPD-01: returns true when 1.10.0 > 1.9.0 (integer, not lexicographic)',
        () {
      expect(UpdateService.isNewerForTest('1.10.0', '1.9.0'), isTrue);
    });

    test('UPD-01: returns false when equal versions', () {
      expect(UpdateService.isNewerForTest('0.1.0', '0.1.0'), isFalse);
    });

    test('UPD-01: returns false when remote is older', () {
      expect(UpdateService.isNewerForTest('0.1.0', '0.2.0'), isFalse);
    });

    test('UPD-01: handles missing segments (treats absent as 0)', () {
      // remote "1.0" vs local "1.0.0" — both effectively 1.0.0
      expect(UpdateService.isNewerForTest('1.0', '1.0.0'), isFalse);
    });

    test('UPD-01: handles short remote with extra local segments', () {
      // remote "1.1" vs local "1.0.9" — 1.1.0 > 1.0.9
      expect(UpdateService.isNewerForTest('1.1', '1.0.9'), isTrue);
    });
  });
}
