# LevelApp Mobile

Flutter companion app for precision inclinometers, over Bluetooth Low Energy.
Android is the primary platform (an iOS scaffold exists but is untested).

**Package:** `com.soldernerd.inclinometer`

## Instruments

| Family | Advertises as | Notes |
|---|---|---|
| Precision level (STM32G0B1 / RN4871) | `Leveltronic-<xxxx>` (the name existing units advertise) | Instruments speaking API v3.1 or newer. Live S1 / S2 / Diff in mm/m, precision measurement, guided calibration (flip zero, phase, gain), all settings, diagnostics and oscilloscope view. |
| NeigMess2 capacitive inclination meter | `NeigMess2…` | API v2 over the same transport. Live tilt and sensors, flip-test zero, tilt trim and neutral calibration. |

Several instruments can be connected at once; the device switcher in the top
bar chooses which one the screens show. Instruments can be given names of
your own. **Open demo instrument** on the scan screen runs a simulated
precision level, so the app can be tried without hardware.

## Development

Needs Flutter 3.50 or newer (the Material widgets come from `material_ui`).

```bash
flutter pub get
flutter analyze
flutter test
flutter run --flavor github     # or --flavor play
```

`flutter run` and `flutter build` need `--flavor github` or `--flavor play`;
`flutter test` and `flutter analyze` do not.

| Flavor | Channel | Self-update |
|---|---|---|
| `github` | GitHub Releases (sideload) | in-app updater |
| `play` | Google Play | compiled out; no `INTERNET` permission |

On Windows, `fl.ps1` wraps `flutter` and clears build directories that OneDrive
locks (`.\fl.ps1 run -d <device>`).

## Releases

Every push to `main` is built by `.github/workflows/ci.yml`: analysis and tests,
then a signed `github` APK published as a GitHub release (`v<major>.<minor>.<n>`,
`major.minor` from `pubspec.yaml`, `n` the commit count) and a `play` app bundle
as a workflow artifact.

## Where things are

Architecture, the device protocol and the conventions are written down in
[`CLAUDE.md`](CLAUDE.md). The device protocol itself is specified in the
instrument firmware repositories. Store listing and privacy policy sources are
in [`docs/`](docs/).
