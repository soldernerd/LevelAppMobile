// TODO(plan-04): Replace placeholder with real widget tests (SCAN-01 through SCAN-05)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inclinometer/ble/mock_ble_manager.dart';
import 'package:inclinometer/models/device_state.dart';
import 'package:inclinometer/providers/device_provider.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  group('ScanScreen — scaffold', () {
    test('placeholder — replaced in plan 04', () {
      expect(true, isTrue);
    });
  });
}
