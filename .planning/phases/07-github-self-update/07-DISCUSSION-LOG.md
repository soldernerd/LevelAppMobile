# Phase 7: GitHub Self-Update - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-07
**Phase:** 7-github-self-update
**Areas discussed:** Check trigger, Dismiss behavior, Download UX

---

## Check Trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Cold start only | Silent check every launch, no extra UI | ✓ |
| Manual button only | User-triggered from About/Settings screen | |
| Both — cold start + manual | Background check plus explicit trigger | |

**User's choice:** Cold start only
**Notes:** No About/Settings screen needed. Simplest path to completing the CI/CD loop.

---

## Dismiss Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Ask again every launch | No persistence, dialog on every cold start until updated | |
| Skip this version | Persist skipped tag; suppress until a newer version is released | ✓ |
| Remind me later | Suppress for current session only | |

**User's choice:** Skip this version
**Notes:** Requires `shared_preferences` to persist the last-skipped tag. Suppress dialog until a higher version tag is detected.

---

## Download UX

| Option | Description | Selected |
|--------|-------------|----------|
| In-app download with progress | dio streams APK to cache, progress %, open_file_plus installs | ✓ |
| Open GitHub release page in browser | User downloads manually | |

**User's choice:** In-app download with progress
**Notes:** True self-update — user just taps "Update" and the system installer appears. Aligns with the CI/CD loop motivation.

---

## Claude's Discretion

- Dialog wording (button labels, version display format)
- Error handling within download flow (cleanup of partial downloads)
- Whether to use `package_info_plus` or build-time version injection — `package_info_plus` chosen as idiomatic

## Deferred Ideas

- iOS update delivery — platform restriction; deferred to future milestone
- In-app changelog (show GitHub release notes body) — nice-to-have, out of scope
- Background periodic update check — cold start sufficient for this tool
