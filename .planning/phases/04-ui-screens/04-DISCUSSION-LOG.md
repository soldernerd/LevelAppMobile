# Phase 4: UI Screens - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 4-UI Screens
**Areas discussed:** Instrument screen layout, Scan screen layout, Stale data indicator, Zero X/Y button feedback

---

## Instrument Screen Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Stacked vertically | X on top, Y below — each label + value pair in its own row | ✓ |
| Side by side | X and Y in two columns — compact but smaller values | |
| Full-screen each, swipeable | One axis per page — max readability, adds navigation complexity | |

**User's choice:** Stacked vertically

---

| Option | Description | Selected |
|--------|-------------|----------|
| Very large ~72–96sp | Dominates the screen, readable across a workbench | ✓ |
| Medium ~48sp | Readable up close, fits more content alongside | |
| You decide | Claude picks size filling ~60% screen height | |

**User's choice:** Very large ~72–96sp

---

| Option | Description | Selected |
|--------|-------------|----------|
| Inline with each value row | Zero X button on the angle_x row; Zero Y on angle_y row | ✓ |
| Grouped at the bottom | Both Zero buttons in a row at screen bottom | |
| You decide | Claude places where they don't interfere with readout | |

**User's choice:** Inline with each value row

---

| Option | Description | Selected |
|--------|-------------|----------|
| AppBar / top bar | Small battery icon + percentage in AppBar — never competes with readout | ✓ |
| Below the angle values | Dedicated battery row under angle_y | |
| You decide | Claude picks least intrusive spot | |

**User's choice:** AppBar / top bar

---

## Scan Screen Layout

| Option | Description | Selected |
|--------|-------------|----------|
| FAB | Floating action button — start/stop scan. Standard Android, thumb-reachable | ✓ |
| AppBar action icon | Play/stop icon in top-right AppBar | |
| Full-width button at top | Prominent button above device list | |

**User's choice:** FAB

---

| Option | Description | Selected |
|--------|-------------|----------|
| AppBar subtitle / status chip below title | Small colored chip — visible but not intrusive | ✓ |
| Banner above device list | Full-width status banner | |
| You decide | Claude picks placement visible in all three states | |

**User's choice:** AppBar subtitle / status chip below title

---

| Option | Description | Selected |
|--------|-------------|----------|
| Name + RSSI bar + RSSI dBm | Signal-strength icon and raw dBm value | ✓ |
| Name + RSSI dBm only | Simple text row, no icon | |
| You decide | Claude picks density fitting a standard ListTile | |

**User's choice:** Name + RSSI bar + RSSI dBm

---

## Stale Data Indicator

| Option | Description | Selected |
|--------|-------------|----------|
| Opacity reduction ~40% | Values fade — clearly not live, but still readable for reference | ✓ |
| Grey overlay with 'Disconnected' badge | Semi-transparent layer over readout area | |
| Replace values with dashes | Unambiguous but discards last-known position | |

**User's choice:** Opacity reduction ~40%

---

| Option | Description | Selected |
|--------|-------------|----------|
| AppBar | Small chip in AppBar alongside disconnect button | ✓ |
| Top of readout area | Chip just above angle values | |
| You decide | Claude places where impossible to miss when disconnected | |

**User's choice:** AppBar

---

| Option | Description | Selected |
|--------|-------------|----------|
| Stay on instrument screen | Stale data + opacity. User navigates back manually. | ✓ |
| Auto-navigate back to scan screen | Route guard fires immediately on disconnect | |

**User's choice:** Stay on instrument screen
**Notes:** Matches oscilloscope/instrument convention — last measurement stays visible.

---

## Zero X/Y Button Feedback

| Option | Description | Selected |
|--------|-------------|----------|
| Silent fire — no UI change | Command fires; readout updating from new zero is the confirmation | ✓ |
| Brief button highlight | Button flashes ~200ms | |
| Snackbar confirmation | 'Zeroed X' snackbar appears briefly | |

**User's choice:** Silent fire — no UI change

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, disable when not connected | Greyed out and non-tappable in disconnected/stale state | ✓ |
| No, always enabled | Tapping while disconnected is a silent no-op | |

**User's choice:** Yes, disable when not connected

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, small debug button in AppBar | Visible in kDebugMode only. Label: "Sim. Disconnect" | ✓ |
| No, test-harness only | simulateDisconnect() called only from widget tests | |

**User's choice:** Yes, small debug button in AppBar (kDebugMode only)

---

## Claude's Discretion

- Exact Material color values for connection chip states (green/amber/red)
- Monospaced font choice for angle values (FontFeature.tabularFigures or system monospace)
- Number of decimal places for angle display
- Animation duration and curve for stale-state opacity transition

## Deferred Ideas

None — discussion stayed within phase scope.
