# Phase 5: App Wiring + Platform Config - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 05-app-wiring-platform-config
**Areas discussed:** Permission flow UX, Route guard behavior, App theme, go_router structure

---

## Permission Flow UX

### Rationale Dialog Timing

| Option | Description | Selected |
|--------|-------------|----------|
| On first app launch | Show rationale before system prompt, every cold start until granted | ✓ |
| Only when user taps Scan | Defer until scan is attempted | |

**User's choice:** On first app launch (Recommended)
**Notes:** Simplest flow; ensures permissions are in place before any BLE interaction.

### Permanently-Denied Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Inline message + Settings button | Persistent message on scan screen with openAppSettings() button | ✓ |
| Full-screen error state | Replace scan screen entirely until permissions granted | |
| Alert dialog + Settings button | Dismissible dialog with settings deep-link | |

**User's choice:** Inline message + Settings button (Recommended)

---

## Route Guard Behavior

### Allowed States for Instrument Screen

| Option | Description | Selected |
|--------|-------------|----------|
| connected only | Redirect to scan for any other state | ✓ |
| connected + reconnecting | Allow during reconnecting state | |
| connected + reconnecting + disconnecting | Stay during any in-progress transition | |

**User's choice:** connected only (Recommended)

### Guard Scope (navigation vs. presence)

| Option | Description | Selected |
|--------|-------------|----------|
| Navigation attempt only | Prevent entry; don't auto-redirect on disconnect | ✓ |
| Also auto-redirect on disconnect | Re-evaluate while on instrument screen | |

**User's choice:** Navigation attempt only (Recommended)
**Notes:** Honors Phase 4 D-10 — stay-on-screen on disconnect. refreshListenable bridge should NOT trigger redirect-on-disconnect.

---

## App Theme

| Option | Description | Selected |
|--------|-------------|----------|
| Dark only — ThemeData.dark() | Single dark theme, consistent with Phase 4 | ✓ |
| System-adaptive | Follow device theme; requires both themes | |
| You decide | Claude picks | |

**User's choice:** Dark only — ThemeData.dark() (Recommended)

---

## go_router Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level final in main.dart | Simple, refreshListenable via custom ChangeNotifier | ✓ |
| Riverpod Provider<GoRouter> | Cleaner Riverpod integration, more complexity | |
| You decide | Claude picks standard pattern | |

**User's choice:** Top-level final variable in main.dart (Recommended)

---

## Claude's Discretion

- Exact wording of rationale dialog and permanently-denied inline message
- Named routes vs. path strings in go_router
- iOS `Info.plist` Bluetooth usage description string wording

## Deferred Ideas

None.
