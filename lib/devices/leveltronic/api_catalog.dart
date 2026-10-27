/// The Settings and Calibrations resources as data: one row per resource with
/// its id, wire type, range and meaning — mirroring `tools/api_spec.py` /
/// `docs/api-reference.md` of the firmware. Drives the generic value editor
/// and the calibration wizards.
library;

import 'dart:typed_data';

import 'package:inclinometer/ble/api_v3.dart';

enum ValType {
  u8(1),
  u16(2),
  i16(2),
  i32(4);

  const ValType(this.bytes);
  final int bytes;

  int decode(Uint8List d) {
    final bd = ByteData.sublistView(d);
    return switch (this) {
      ValType.u8 => d[0],
      ValType.u16 => bd.getUint16(0, Endian.little),
      ValType.i16 => bd.getInt16(0, Endian.little),
      ValType.i32 => bd.getInt32(0, Endian.little),
    };
  }

  Uint8List encode(int v) {
    final b = Uint8List(bytes);
    final bd = ByteData.sublistView(b);
    switch (this) {
      case ValType.u8:
        b[0] = v;
      case ValType.u16:
        bd.setUint16(0, v, Endian.little);
      case ValType.i16:
        bd.setInt16(0, v, Endian.little);
      case ValType.i32:
        bd.setInt32(0, v, Endian.little);
    }
    return b;
  }

  bool covers(Uint8List d) => d.length >= bytes;
}

/// One Settings or Calibrations resource.
class ApiValueDef {
  const ApiValueDef({
    required this.category,
    required this.id,
    required this.label,
    required this.description,
    required this.type,
    required this.min,
    required this.max,
    this.unit = '',
    this.service = false,
    this.optional = false,
    this.group = '',
  });

  /// [ApiCat.settings] or [ApiCat.calibrations].
  final int category;
  final int id;
  final String label;
  final String description;
  final ValType type;
  final int min, max;

  /// Unit of the raw integer, shown next to it (e.g. `mV`, `ppm`, `0.01°`).
  final String unit;

  /// Writes need service mode.
  final bool service;

  /// Not present in every firmware build; a GET answering UNKNOWN_RESOURCE
  /// simply hides the row.
  final bool optional;
  final String group;

  int get getOpcode => opGet(category, id);
  int get setOpcode => opSet(category, id);
}

const _s = ApiCat.settings;
const _c = ApiCat.calibrations;

/// Settings (category 0x3). Ranges are the firmware's.
const List<ApiValueDef> kSettings = [
  ApiValueDef(
    category: _s,
    id: 0x60,
    label: 'Auto power-off',
    description:
        'Idle time with no encoder input before the instrument powers off '
        '(0 = never).',
    type: ValType.u16,
    min: 0,
    max: 65535,
    unit: 's',
    group: 'Power',
  ),
  ApiValueDef(
    category: _s,
    id: 0x52,
    label: 'Charge start voltage',
    description:
        'Below this battery voltage, with USB power present, charging starts.',
    type: ValType.u16,
    min: 3000,
    max: 4200,
    unit: 'mV',
    group: 'Power',
  ),
  ApiValueDef(
    category: _s,
    id: 0x53,
    label: 'Max time at 100 %',
    description:
        'Charging stops after this many minutes at a full battery. Only '
        'present in firmware builds that support it.',
    type: ValType.u16,
    min: 0,
    max: 65535,
    unit: 'min',
    optional: true,
    group: 'Power',
  ),
  ApiValueDef(
    category: _s,
    id: 0x51,
    label: 'Battery low warning',
    description:
        'Below this voltage the low-battery warning shows (must stay above '
        '"Battery critical").',
    type: ValType.u16,
    min: 3000,
    max: 4200,
    unit: 'mV',
    group: 'Power',
  ),
  ApiValueDef(
    category: _s,
    id: 0x50,
    label: 'Battery critical',
    description:
        'Below this voltage the instrument powers off (must stay below '
        '"Battery low warning").',
    type: ValType.u16,
    min: 2500,
    max: 3600,
    unit: 'mV',
    group: 'Power',
  ),
  ApiValueDef(
    category: _s,
    id: 0x61,
    label: 'Encoder counts per detent',
    description:
        'Raw quadrature transitions per mechanical detent of the rotary '
        'encoders.',
    type: ValType.u16,
    min: 1,
    max: 100,
    group: 'Instrument',
  ),
  ApiValueDef(
    category: _s,
    id: 0x40,
    label: 'Sensor task period',
    description: 'How often the sensor task runs.',
    type: ValType.u16,
    min: 1,
    max: 1000,
    unit: 'ms',
    group: 'Task periods',
  ),
  ApiValueDef(
    category: _s,
    id: 0x41,
    label: 'BLE task period',
    description: 'How often the BLE task runs.',
    type: ValType.u16,
    min: 1,
    max: 250,
    unit: 'ms',
    group: 'Task periods',
  ),
  ApiValueDef(
    category: _s,
    id: 0x42,
    label: 'USB task period',
    description: 'How often the USB task runs.',
    type: ValType.u16,
    min: 1,
    max: 250,
    unit: 'ms',
    group: 'Task periods',
  ),
  ApiValueDef(
    category: _s,
    id: 0x43,
    label: 'Battery task period',
    description: 'How often the battery task runs.',
    type: ValType.u16,
    min: 100,
    max: 10000,
    unit: 'ms',
    group: 'Task periods',
  ),
  ApiValueDef(
    category: _s,
    id: 0x44,
    label: 'Temperature task period',
    description: 'How often the temperature task runs.',
    type: ValType.u16,
    min: 100,
    max: 60000,
    unit: 'ms',
    group: 'Task periods',
  ),
];

// Sensor calibrations — referenced by the wizards.
const ApiValueDef kS1K = ApiValueDef(
  category: _c,
  id: 0x40,
  label: 'S1 sensitivity k',
  description:
      'tilt [mm/m] = (ratio − zero) / k, at PGA 1. Unit: 1e-6 per mm/m.',
  type: ValType.i32,
  min: 100,
  max: 1000000,
  service: true,
  group: 'Sensor 1',
);
const ApiValueDef kS1Zero = ApiValueDef(
  category: _c,
  id: 0x41,
  label: 'S1 zero',
  description: 'Level point of sensor 1 as a ratio, independent of k.',
  type: ValType.i32,
  min: -500000,
  max: 500000,
  unit: 'ppm',
  service: true,
  group: 'Sensor 1',
);
const ApiValueDef kS1Phase = ApiValueDef(
  category: _c,
  id: 0x42,
  label: 'S1 phase',
  description:
      'Phase of the tilt signal relative to the excitation reference.',
  type: ValType.i16,
  min: -4500,
  max: 4500,
  unit: '0.01°',
  service: true,
  group: 'Sensor 1',
);
const ApiValueDef kS1Invert = ApiValueDef(
  category: _c,
  id: 0x43,
  label: 'S1 invert',
  description: 'Sign of the reported reading (1 = inverted).',
  type: ValType.u8,
  min: 0,
  max: 1,
  service: true,
  group: 'Sensor 1',
);
const ApiValueDef kS2K = ApiValueDef(
  category: _c,
  id: 0x44,
  label: 'S2 sensitivity k',
  description:
      'tilt [mm/m] = (ratio − zero) / k, at PGA 1. Unit: 1e-6 per mm/m.',
  type: ValType.i32,
  min: 100,
  max: 1000000,
  service: true,
  group: 'Sensor 2',
);
const ApiValueDef kS2Zero = ApiValueDef(
  category: _c,
  id: 0x45,
  label: 'S2 zero',
  description: 'Level point of sensor 2 as a ratio, independent of k.',
  type: ValType.i32,
  min: -500000,
  max: 500000,
  unit: 'ppm',
  service: true,
  group: 'Sensor 2',
);
const ApiValueDef kS2Phase = ApiValueDef(
  category: _c,
  id: 0x46,
  label: 'S2 phase',
  description:
      'Phase of the tilt signal relative to the excitation reference.',
  type: ValType.i16,
  min: -4500,
  max: 4500,
  unit: '0.01°',
  service: true,
  group: 'Sensor 2',
);
const ApiValueDef kS2Invert = ApiValueDef(
  category: _c,
  id: 0x47,
  label: 'S2 invert',
  description: 'Sign of the reported reading (1 = inverted).',
  type: ValType.u8,
  min: 0,
  max: 1,
  service: true,
  group: 'Sensor 2',
);

/// Per-sensor calibration definitions, index 0 = S1, 1 = S2.
const List<ApiValueDef> kSensorK = [kS1K, kS2K];
const List<ApiValueDef> kSensorZero = [kS1Zero, kS2Zero];
const List<ApiValueDef> kSensorPhase = [kS1Phase, kS2Phase];
const List<ApiValueDef> kSensorInvert = [kS1Invert, kS2Invert];

/// All calibrations, for the generic editor (service mode to write).
const List<ApiValueDef> kCalibrations = [
  kS1K,
  kS1Zero,
  kS1Phase,
  kS1Invert,
  kS2K,
  kS2Zero,
  kS2Phase,
  kS2Invert,
  ApiValueDef(
    category: _c,
    id: 0x50,
    label: 'Battery scale numerator',
    description: 'Vbat = Vadc × num / den + offset.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Battery voltage',
  ),
  ApiValueDef(
    category: _c,
    id: 0x51,
    label: 'Battery scale denominator',
    description: 'Vbat = Vadc × num / den + offset.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Battery voltage',
  ),
  ApiValueDef(
    category: _c,
    id: 0x52,
    label: 'Battery voltage offset',
    description: 'Additive correction of the battery voltage.',
    type: ValType.i32,
    min: -500,
    max: 500,
    unit: 'mV',
    service: true,
    group: 'Battery voltage',
  ),
  ApiValueDef(
    category: _c,
    id: 0x70,
    label: 'Clock trim',
    description:
        'Positive makes the clock run faster. About 0.95 ppm per step.',
    type: ValType.i16,
    min: -4800,
    max: 4800,
    unit: '0.1 ppm',
    service: true,
    group: 'Clock',
  ),
  ApiValueDef(
    category: _c,
    id: 0x68,
    label: 'External LM35 scale',
    description: 'Scale of the external temperature sensor.',
    type: ValType.u16,
    min: 1,
    max: 1000,
    unit: 'mV/°C',
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x60,
    label: 'TMP236 seg. 1 offset',
    description: 'TMP236 segment 1 voltage offset.',
    type: ValType.u16,
    min: 0,
    max: 3300,
    unit: 'mV',
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x61,
    label: 'TMP236 seg. 1 slope num.',
    description: 'TMP236 segment 1 slope numerator.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x62,
    label: 'TMP236 seg. 1 slope den.',
    description: 'TMP236 segment 1 slope denominator.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x63,
    label: 'TMP236 segment boundary',
    description: 'TMP236 segment boundary.',
    type: ValType.u16,
    min: 0,
    max: 3300,
    unit: 'mV',
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x64,
    label: 'TMP236 seg. 2 offset',
    description: 'TMP236 segment 2 voltage offset.',
    type: ValType.u16,
    min: 0,
    max: 3300,
    unit: 'mV',
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x65,
    label: 'TMP236 seg. 2 slope num.',
    description: 'TMP236 segment 2 slope numerator.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x66,
    label: 'TMP236 seg. 2 slope den.',
    description: 'TMP236 segment 2 slope denominator.',
    type: ValType.u16,
    min: 1,
    max: 10000,
    service: true,
    group: 'Temperature sensors',
  ),
  ApiValueDef(
    category: _c,
    id: 0x67,
    label: 'TMP236 seg. 2 inflection',
    description: 'TMP236 segment 2 inflection temperature.',
    type: ValType.u16,
    min: 0,
    max: 20000,
    unit: '0.01 °C',
    service: true,
    group: 'Temperature sensors',
  ),
];
