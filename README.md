# Buckle Link

An unofficial, free and open-source iOS companion app for the Sony Wena 3 smartwatch band.

Sony ended Wena 3 support and services on 28 February 2026, so its official app can no longer set up or update the band. Buckle Link aims to keep already-set-up bands useful on iPhone. It is a non-profit hobby project with no ads.

> **Not affiliated with, endorsed by or connected to Sony.** "Sony" and "Wena" are trademarks of their respective owners and are used here only to describe which device this app works with.

## Status

Early days. The project is set up and builds, but no Bluetooth features exist yet.

Planned, in this order:

1. Connect to an already-paired band, show firmware version and battery level (read-only)
2. Time and time zone sync
3. Weather
4. Calendar
5. Band settings
6. Activity and heart rate into Apple Health (needs band firmware 2.40 or later)

Notifications are not on the list because iPhone already sends them to the band through Apple's standard accessory notification service (ANCS), with no app needed.

Not possible: Suica, Alexa, Riiiver, MAMORIO, Qrio and other features that relied on Sony's servers. Firmware updates are out of scope.

## A word of caution

- Do not factory-reset your band or remove it from iPhone Bluetooth settings. Without Sony's app, a reset band may not be possible to set up again.
- This app is experimental. It only sends the band commands that have been documented and checked, but use it at your own risk.

## Building

Requirements: a Mac with Xcode 27.2 or later, and an iPhone on iOS 27.2 or later. The iOS Simulator has no Bluetooth, so band features need a real iPhone.

1. Open `WenaCompanion.xcodeproj` in Xcode.
2. Pick your iPhone (with Developer Mode on) or a simulator as the run destination.
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
