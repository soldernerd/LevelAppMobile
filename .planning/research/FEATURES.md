# Features Research

**Domain:** BLE companion app for precision 2-axis inclinometer (machine shop)
**Researched:** 2026-06-04
**Confidence:** HIGH for BLE UX patterns (multiple authoritative sources); HIGH for inclinometer domain features (Digi-Pas direct inspection); MEDIUM for display/update-rate specifics (hardware docs + community corroboration)

---

## Table Stakes

Features users expect in any BLE instrument companion app. Missing = product feels broken or unprofessional.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Scan screen with live device list** | Users need to find and select their specific instrument | Low | Name + RSSI per row; filter by device name prefix so users are not shown every nearby BLE device |
| **RSSI indicator in scan list** | Tells user which device is theirs and how close it is | Low | Icon (strong/medium/weak) is enough; raw dBm acceptable but not required |
| **Tap-to-connect with progress feedback** | Zero tolerance for silent hangs — user must see "connecting…" | Low | Spinner or animated status text; BLE connection can take several seconds |
| **Connection state visible at all times on instrument screen** | User needs to know if readings are live or stale | Low | Status bar / chip: Connected (green) / Reconnecting (amber) / Disconnected (red) |
| **Large, high-contrast angle readout** | Machine shop environment — glare, distance, gloves | Low | Primary content at ≥48sp; both axes simultaneously visible |
| **Decimal precision matching sensor resolution** | 0.01° display matches SCL3300 sensor capability and matches what professional instruments show | Low | Two decimal places (e.g. "–12.34°"); more is noise from float jitter |
| **Zero X / Zero Y controls** | Core use case: relative measurement against a datum surface | Low | Already planned; buttons clearly labeled, placed for one-hand use |
| **Battery level indicator** | Users leave instrument on metal surfaces — dead battery wastes a session | Low | Percentage or icon; already in BLE protocol (uint8) |
| **Disconnect button** | Users expect to cleanly disconnect rather than walk away | Low | Graceful GATT disconnect, returns to scan screen |
| **Stale data indicator on disconnect** | When BLE drops, last reading must be visually dimmed/greyed — do NOT leave it looking live | Low | Overlay or opacity change + "Last seen X seconds ago" or "Disconnected" badge |
| **Auto-reconnect on transient drop** | Instrument may go briefly out of range in shop; users expect silent recovery | Medium | Exponential backoff (e.g. 1s → 2s → 4s → 8s, cap at 30s); show "Reconnecting…" not a hard error; already stubbed in WP1 |
| **Remembered device (skip re-scan)** | After first connect, user should not have to scan every session | Medium | Persist last-connected device ID; on app launch attempt direct reconnect before showing scan screen |
| **Android BLE permissions handled gracefully** | App crashes or shows blank screen if permissions are denied — users blame the app | Low | Already planned via permission_handler; show rationale dialog before requesting |

---

## Differentiators

Features that set this app apart from a generic BLE viewer. Not expected, but valued by professional users.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Hold / Freeze reading** | Machine shop: instrument is placed, user steps back to phone; freeze captures the reading at that moment so user can write it down or photograph it | Low | Single button that stops updating the display; held values visually distinguished (e.g. blue tint, "HOLD" label); does not disconnect; resumes on second press |
| **Units toggle: degrees / mm·m⁻¹ / %** | Machinists and millwrights often specify levelling in mm/m (e.g. "0.05 mm/m") not degrees; direct conversion avoids mental arithmetic errors | Low | Pure math (mm/m = tan(θ) × 1000; % = tan(θ) × 100); toggle persists to SharedPreferences; shown below main readout |
| **2D bubble / graphical level display** | Intuitive at-a-glance sense of both axes simultaneously — every competing product (Digi-Pas, SOLA) includes this | Medium | Canvas widget: crosshair that moves within circle; purely additive — primary numeric readout stays |
| **Configurable update rate throttle** | SCL3300 can send data fast; at 20–50 Hz the display is unreadably jittery; user should pick 2 Hz / 5 Hz / 10 Hz | Low | Throttle in the BLE stream handler (not the hardware); SharedPreferences |
| **Session log / measurement capture** | "Tap to record this reading" — builds a timestamped list of angle_x + angle_y snapshots; export as CSV | Medium | Local SQLite (drift or sqflite); CSV share via platform share sheet; no cloud dependency |
| **Relative zero memory** | User zeros the instrument, later wants to restore it to absolute; show current zero offset alongside live reading | Low | Store zero offsets from firmware in app state; display as "Offset X: +2.34°" |
| **Screen-on lock during measurement** | Phone screen dims mid-measurement in a shop — infuriating | Low | WakelockPlus package; auto-acquired when connected, released on disconnect |
| **Font size / display density setting** | Shop-floor use: user may be 2 m from phone on a bench; let them make the readout even larger | Low | Three preset sizes stored in settings; simple preference screen |

---

## Anti-Features

Things to deliberately NOT build. These attract complexity disproportionate to their value for this use case.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Cloud sync / account system** | Machine shop instruments are single-user, single-device, air-gapped shop environments; adds auth complexity, privacy surface, and dependency on external services for no measurable benefit | Local-only SQLite for logs; share via system share sheet (email, AirDrop, USB) |
| **Real-time graphing / time-series chart** | Angle readings don't need trend analysis during normal use; the SCL3300 is a static levelling sensor, not a vibration logger; a live graph is visual noise that doesn't help a machinist | Show numeric value clearly; add Hold feature instead |
| **Vibration monitoring / FFT** | Digi-Pas markets this; it requires a different sensor mode, a fundamentally different UX, and a different user task entirely | Out of scope; SCL3300-D01 is a tilt sensor, not an accelerometer for vibration |
| **Calibration UI exposed to user** | Factory calibration of the SCL3300 uses an internal algorithm; exposing user-facing calibration creates liability if done wrong and is unsupported by the simple BLE protocol (single-byte commands only) | The zero function (ZERO_X / ZERO_Y) covers the legitimate user need |
| **Multi-device support** | Managing multiple simultaneous BLE connections is a significant architectural complication (GATT client multiplexing, UI split, state fan-out); this instrument is one device per user | Single-device connection model is sufficient and simpler |
| **OTA firmware update** | Requires a DFU protocol (Nordic or ST-specific), a second BLE service, file management UI, and careful error recovery; STM32G0B1 bootloader support is unknown | If firmware updates become needed, build as a separate utility app or use vendor tooling |
| **User accounts / measurement sharing to colleagues** | Adds back-end, onboarding, and trust model to a tool that is fundamentally solo | CSV export to email achieves 95% of the collaboration value at 5% of the complexity |
| **Custom themes / skins** | Visual customisation has no precision measurement value; deferred in PROJECT.md already | System light/dark follows platform; revisit only if user research strongly demands it |

---

## Feature Complexity Notes

Effort estimates for non-obvious features, ordered from easiest to hardest.

### Screen-on lock — trivial (< 1 hour)
`wakelock_plus` package; single call on connect event, release on disconnect. No UI needed.

### Units toggle (degrees / mm·m⁻¹ / %) — trivial (< 2 hours)
Pure math transform applied at display layer. Store unit preference in `shared_preferences`. No BLE protocol change. Formula: `mm_per_m = tan(radians(angle)) * 1000`.

### Hold / Freeze reading — low (2–4 hours)
Add a `bool isHeld` flag and a `heldSnapshot` to the instrument state provider. When held, the display reads from snapshot, not from live BLE stream. The BLE subscription continues (prevents reconnect thrashing). Visual badge and colour shift.

### Remembered device / skip-scan reconnect — low (3–5 hours)
Persist device ID to `shared_preferences` on first successful connect. On app launch, check for saved ID and attempt direct GATT connect via `flutter_blue_plus` `connect()` (not scan). Show scan screen only if connect times out. The auto-reconnect stub already in WP1 is the right place to wire this.

### Configurable update rate throttle — low (2–3 hours)
Add a `throttleDuration` setting (e.g. 50ms = 20 Hz, 100ms = 10 Hz, 200ms = 5 Hz, 500ms = 2 Hz). In the BLE stream handler, use `throttleTime()` from `rxdart` or a manual timestamp check. UI is a simple `DropdownButton` in settings.

### Stale data / disconnected state overlay — low (2–4 hours)
When connection state transitions to `disconnected`, provider preserves last values but sets a `isStale` flag. Display layer: opacity 0.4 on readings, overlay badge "DISCONNECTED — last seen MM:SS ago". Timer updates the elapsed display. On reconnect, `isStale` clears and opacity restores.

### Relative zero memory / offset display — low (2–3 hours)
The firmware handles zeroing (ZERO_X / ZERO_Y commands). The app can optionally track the angle reading at the moment Zero was pressed and display it as the current offset. No protocol changes needed — it is purely a UI tracking concern.

### 2D bubble display — medium (1–2 days)
Custom `CustomPainter` widget drawing concentric circles and a filled-circle cursor at `(angle_x, angle_y)` coordinates. Non-trivial because: auto-scaling range (zoom in when readings are close to zero), clamp cursor to circle boundary, smooth animation between frames. Not complex algorithmically but needs iteration for good feel.

### Session log + CSV export — medium (1–2 days)
Add `sqflite` (or `drift`), define a `measurements` table with `(id, timestamp, angle_x, angle_y, unit, note)`. "Capture" button inserts a row. History screen with `ListView`. Export taps `share_plus` with a generated CSV string. No networking. The hidden complexity is the UI for reviewing, deleting, and annotating entries.

### Font size / display density setting — low (2–4 hours)
Wrap readout text in a provider-driven `TextStyle` that picks from three preset sizes. A settings screen with three radio buttons. `shared_preferences` for persistence.

---

## Display Specifics (Precision Instrument Standards)

Based on competing products (Digi-Pas DWL series, SOLA Go! Smart, PRO3600) and sensor specs:

- **Decimal places**: 2 (e.g. `–12.34°`). The SCL3300-D01 has ~0.01° resolution; two decimal places reflects real precision. Three decimals are noise from float representation and vibration.
- **Update rate**: Throttle UI to 5–10 Hz for comfortable reading. Raw BLE notification rate from the MCU will be faster; throttle in Flutter, not firmware. Digi-Pas displays update at approximately 2–3 Hz for the numeric readout.
- **Sign convention**: Display sign explicitly. `+` for positive, `–` for negative. Never suppress the `+` sign — machinists need to know which direction the tilt is.
- **Near-zero behaviour**: Do NOT zero-suppress below some threshold (e.g. show `0.00°` not `---`). Users need to see the reading approach zero as they level.
- **Font**: Monospaced or tabular numerals preferred — prevents layout shift as digits change. Flutter: `fontFeatures: [FontFeature.tabularFigures()]`.

---

## Connection Management UX States (Exhaustive)

The complete state machine the UI must surface to users:

| State | What to Show | User Action Available |
|-------|-------------|----------------------|
| Bluetooth off | "Enable Bluetooth to continue" with system settings shortcut | Tap to open Settings |
| Permission denied | "Bluetooth permission required" with rationale and retry | Tap to re-request / open Settings |
| Idle (not scanning) | Scan button prominent | Tap Scan |
| Scanning | Spinner + "Scanning…" + live device list populates | Tap device to connect; tap Stop |
| Scan error (error code 2 = already scanning; code 3 = throttled by OS) | "Scan failed — wait a moment and try again" | Tap Retry after brief delay |
| Connecting | "Connecting to [device name]…" spinner | Tap Cancel |
| Connected | Instrument screen, green status indicator | Disconnect button |
| Disconnected unexpectedly | Stale overlay on readings + "Reconnecting…" amber indicator | Tap Forget (returns to scan screen) |
| Reconnect failed (max retries) | "Could not reconnect — tap to scan again" | Tap to return to scan screen |
| User-initiated disconnect | Returns to scan screen cleanly | — |

---

## Sources

- Digi-Pas Level App feature page (direct inspection): http://www.digipas.com/product/precision-measurement/2-axis-ultra-precision-inclinometer/digipas-mobile-app.php
- Digi-Pas DWL-8500XY product page: https://www.digipas.com/product/precision-measurement/2-axis-ultra-precision-inclinometer/dwl-8500xy.php
- Punch Through: The Ultimate Guide To Managing Your BLE Connection: https://punchthrough.com/manage-ble-connection/
- Punch Through: Android BLE Guide: https://punchthrough.com/android-ble-guide/
- Sparkleo: Advanced BLE Development with Flutter Blue Plus: https://medium.com/@sparkleo/advanced-ble-development-with-flutter-blue-plus-ec6dd17bf275
- Stormotion: BLE Companion App Development Guide: https://stormotion.io/blog/how-to-build-a-companion-app-for-your-iot-ble-device/
- Bosch MeasureOn app (companion instrument pattern reference): https://www.bosch-professional.com/gb/en/measureon/
- PRO3600 Digital Protractor 0.01° resolution: https://www.leveldevelopments.com/products/inclinometers/digital-inclinometers/pro3600-digital-protractor-range-360-resolution-0-01/
- Robust BLE reconnect on Android 12+: https://dev.to/ble_advertiser/robust-ble-preventing-disconnections-and-implementing-auto-reconnect-on-android-12-with-in8
- Digi-Pas Smart Level App (machinist level companion): https://www.digipas.com/product/precision-measurement/2-axis-precision-digital-machinist-level/digipas-smart-level.php
