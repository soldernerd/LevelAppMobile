/// Which sensors a calibration run covers: bit0 S1, bit1 S2.
class SensorMask {
  static const s1 = 1;
  static const s2 = 2;
  static const both = 3;

  static bool has(int mask, int sensorIndex) => mask & (1 << sensorIndex) != 0;
  static String label(int mask) => switch (mask) {
        s1 => 'S1',
        s2 => 'S2',
        _ => 'S1 and S2',
      };
}
