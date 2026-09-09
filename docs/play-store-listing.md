# Google Play — listing & declaration reference

Working copy of everything to paste into the Play Console. Not shipped in the app.

## Identity

| Field | Value |
|---|---|
| App name (≤30 chars) | `Leveltronic` |
| Package name (permanent) | `com.soldernerd.inclinometer` |
| Category | Tools |
| Free / Paid | Free |
| Contains ads | No |
| Default language | English (United States) |

## Short description (≤80 chars)

```
Live readings from your Leveltronic precision level over Bluetooth.
```

## Full description (≤4000 chars)

```
Leveltronic is the companion app for the Leveltronic precision level
instrument. Connect over Bluetooth Low Energy to see the instrument's
measurements live on your phone:

• Battery voltage, charge level and state
• On-board, external-probe and ambient (BME280) temperature
• Relative humidity and barometric pressure
• USB / charging status

The app scans for nearby Leveltronic instruments, connects with one tap,
and streams readings continuously. When the link drops, the last values
are greyed out and marked stale so you never mistake them for live data.

No account, no sign-in, no data collection. Bluetooth is used only to talk
to your own instrument; nothing is recorded or sent anywhere.

Tilt / angle readout is shown as a placeholder in this version — the
current instrument firmware does not yet expose an angle value.
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

## Store assets still needed

| Asset | Spec |
|---|---|
| App icon | 512×512 PNG, 32-bit, <1 MB |
| Feature graphic | 1024×500 PNG/JPG |
| Phone screenshots | ≥2, 16:9 or 9:16, each 320–3840 px |
| (optional) 7"/10" tablet screenshots | only if you list tablet support |

## Enabling the privacy-policy URL (GitHub Pages)

1. Repo → Settings → Pages
2. Source: "Deploy from a branch", branch `main`, folder `/docs`
3. Save. The policy is then live at
   `https://soldernerd.github.io/LevelAppMobile/privacy-policy`
4. Fill in the contact email in `docs/privacy-policy.md` before relying on it.
