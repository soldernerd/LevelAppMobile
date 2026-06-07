---
status: partial
phase: 07-github-self-update
source: [07-VERIFICATION.md]
started: 2026-06-07T00:00:00Z
updated: 2026-06-07T00:00:00Z
---

## Current Test

[awaiting human testing on physical Android device]

## Tests

### 1. Cold start update dialog (end-to-end)
expected: AlertDialog appears naming the new release version with Skip and Update buttons; tapping Update downloads the APK and shows a LinearProgressIndicator, then launches the Android package installer
result: [pending]

### 2. Silent fail in airplane mode
expected: App loads normally with no error dialog, no crash — update check fails silently
result: [pending]

### 3. Skip persistence across process restart
expected: The update dialog does NOT reappear for the same version tag on the second cold start after tapping Skip
result: [pending]

### 4. Download progress + installer launch
expected: LinearProgressIndicator shows percentage rising from 0% to 100% as download progresses; after download the Android installer screen appears
result: [pending]

### 5. REQUEST_INSTALL_PACKAGES redirect (Android 8+)
expected: User is redirected to Settings to grant "Install unknown apps" permission before download begins
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
