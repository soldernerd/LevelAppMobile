// test/update_service_test.dart
// Unit tests for UpdateService — UPD-01, UPD-05.
// Covers _isNewer version comparison logic (integer-per-segment, not lexicographic)
// and skipVersion SharedPreferences persistence.

import 'package:flutter_test/flutter_test.dart';
import 'package:inclinometer/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('UPD-01: major version bump 2.0.0 > 1.9.9', () {
      expect(UpdateService.isNewerForTest('2.0.0', '1.9.9'), isTrue);
    });

    test('UPD-01: patch increment 1.2.4 > 1.2.3', () {
      expect(UpdateService.isNewerForTest('1.2.4', '1.2.3'), isTrue);
    });

    test('UPD-01: non-numeric segment treated as 0 (1.0.beta == 1.0.0)', () {
      // "beta" → int.tryParse returns null → 0, so 1.0.0 == 1.0.0 → false
      expect(UpdateService.isNewerForTest('1.0.beta', '1.0.0'), isFalse);
    });

    test('UPD-01: single-segment comparison 2 > 1', () {
      // "2" expands to [2,0,0]; "1" expands to [1,0,0]
      expect(UpdateService.isNewerForTest('2', '1'), isTrue);
    });
  });

  group('UpdateService.skipVersion persistence', () {
    setUp(() {
      // Reset shared_preferences to a clean in-memory store before each test.
      SharedPreferences.setMockInitialValues({});
    });

    test('skipVersion stores tagName under skipped_update_version key', () async {
      // Arrange
      const tag = 'v0.1.1';

      // Act
      await UpdateService.skipVersion(tag);

      // Assert
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('skipped_update_version'), equals(tag));
    });

    test('skipVersion overwrites the previous skipped tag', () async {
      // Arrange — skip one version first
      await UpdateService.skipVersion('v0.1.0');

      // Act — skip a newer version
      await UpdateService.skipVersion('v0.1.1');

      // Assert — only the last tag is stored
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('skipped_update_version'), equals('v0.1.1'));
    });
  });
}
