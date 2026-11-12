# Google Play — listing & declaration reference

Working copy of everything to paste into the Play Console. Not shipped in the app.

## Identity

| Field | Value |
|---|---|
| App name (≤30 chars) | `LevelApp Mobile` |
| Package name (permanent) | `com.soldernerd.inclinometer` |
| Category | Tools |
| Free / Paid | Free |
| Contains ads | No |
| Default language | English (United States) |

## Short description (≤80 chars)

```
Live readings and calibration for your precision level over Bluetooth.
```

## Full description (≤4000 chars)

```
LevelApp Mobile is a companion app for precision level instruments. Connect
over Bluetooth Low Energy and use your phone as a large, readable display and
remote control:

• Live readings: S1, S2 and the difference (S1 − S2) in mm/m, large and
  steady, with a vibration indicator that warns when the table is not quiet
• Zero the difference at the touch of a button
• Precision measurement: the instrument waits for a quiet moment and reports
  one reliable value
• Guided calibration: zero (180° flip), phase and sensitivity (gain), for one
  sensor or both, with before/after values
• All settings in one place: auto power-off, charging threshold, battery
  limits, power off, force charge and more
• All values: battery voltage and state of charge, temperatures, humidity,
  pressure, clock
• Signal diagnostics: RMS, peak-to-peak and phase of all four channels

The battery level and charging state are always visible. No account, no
sign-in, no data collection: Bluetooth is used only to talk to your own
instrument; nothing is recorded or sent anywhere.

Requires an instrument that speaks API 3.1 (firmware 0.15 or newer).
```

## Privacy policy URL

`https://soldernerd.github.io/LevelAppMobile/privacy-policy` (after enabling
GitHub Pages — see below).

## App access

All functionality is available without any special access, login, or account.

## Data safety form

- Does your app collect or share any of the required user data types? **No**
- Is all user data encrypted in transit? **N/A (no data collected)**
- Do you provide a way for users to request deletion? **N/A**

## Content rating questionnaire

- Category: Utility, Productivity, Communication, or Other
- Violence / sexual / language / controlled substances / etc.: **No** to all
- Expected result: **Everyone**

## Target audience

- Target age group: 18+ (tool for use with measurement hardware)
- Appeals to children: No

## Other declarations

- News app: No
- COVID-19 contact tracing / status: No
- Government app: No
- Financial features: None
- Health: Not a health app; makes no health claims

## Store assets

All in this repo; upload them as they are.

| Asset | Spec | File |
|---|---|---|
| App icon | 512×512 PNG, 32-bit, <1 MB | `docs/store-graphics/app-icon-512.png` (full-bleed square; Play rounds it) |
| Feature graphic | 1024×500 PNG/JPG | `docs/store-graphics/feature-graphic-1024x500.png` |
| Phone screenshots | ≥2, 16:9 or 9:16 (long side at most 2× the short), each 320–3840 px | `docs/Screenshots/play/01-live.jpg` to `05-settings.jpg` (1080×2160) |
| (optional) 7"/10" tablet screenshots | only if you list tablet support |

## Enabling the privacy-policy URL (GitHub Pages)

1. Repo → Settings → Pages
2. Source: "Deploy from a branch", branch `main`, folder `/docs`
3. Save. The policy is then live at
   `https://soldernerd.github.io/LevelAppMobile/privacy-policy`
4. Fill in the contact email in `docs/privacy-policy.md` before relying on it.
