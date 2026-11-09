# Anew Link

An unofficial, free and open-source iOS companion app for the Sony Wena 3 smartwatch band.

Sony ended Wena 3 support and services on 28 February 2026, so its official app can no longer set up or update the band. Anew Link aims to keep already-set-up bands useful on iPhone. It is a non-profit hobby project with no ads.

> **Not affiliated with, endorsed by or connected to Sony.** "Sony" and "Wena" are trademarks of their respective owners and are used here only to describe which device this app works with.

## Status

Working on a real band (tested on firmware 2.40JP):

- Firmware, battery and serial (read-only)
- Time and time zone, kept right automatically
- 5-day weather, updated automatically (every 2 to 3 hours at most), also with the phone locked
- Steps and heart rate saved to Apple Health automatically, about every 2 hours
- Song title from Apple Music on the band's music screen
- Find my phone: the band's find-phone button rings the iPhone
- Your upcoming calendar events on the band
- Stays connected in the background and reconnects by itself
- Demo mode, to try every screen without a band



Next: alarms and band settings (vibration, display, do not disturb), one packet at a time.

Notifications, calls and the band's music controls already work through iOS with no app needed (Apple's standard accessory services).

Not possible: Suica, iD, QUICPay, Alexa, Riiiver and Qrio, which relied on Sony's or other companies' servers. Firmware updates are out of scope. MAMORIO runs through its own app.

Privacy: no accounts, no analytics, nothing sent to us. See [`Docs/privacy-policy.md`](Docs/privacy-policy.md).

## A word of caution

- Do not factory-reset your band or remove it from iPhone Bluetooth settings. Without Sony's app, a reset band may not be possible to set up again.
- This app is experimental. It only sends the band commands that have been documented and checked, but use it at your own risk.

## Building

Requirements: a Mac with Xcode 27.2 or later, and an iPhone on iOS 27.2 or later. The iOS Simulator has no Bluetooth, so band features need a real iPhone.

1. Open `WenaCompanion.xcodeproj` in Xcode.
2. Pick your iPhone (with Developer Mode on) or a simulator as the run destination. In the simulator, tap **Try the demo**.
3. Press Cmd+R.

Or from the terminal:

```bash
xcodebuild -project WenaCompanion.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build
```

## How it works

The band talks to the phone over Bluetooth Low Energy. The protocol is described in [`Docs/wena3-protocol-spec.md`](Docs/wena3-protocol-spec.md), and the project plan is in [`Docs/wena3-ios-companion-plan.md`](Docs/wena3-ios-companion-plan.md).

This app is a clean-room implementation: it is written from that protocol description, not from other projects' source code.

## Credits

Huge thanks to the [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge) project and the author of its Wena 3 support, whose work on Android made it possible to understand how the band communicates.

## Licence

[MIT](LICENSE)
