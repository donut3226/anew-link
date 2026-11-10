# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About this project

Free, open-source, non-profit iOS companion app for the Sony Wena 3 band, built by a beginner as a first app. Swift, SwiftUI, CoreBluetooth. Read `Docs/` first (the plan and the protocol spec).

## Rules

- Clean-room: implement from `Docs/wena3-protocol-spec.md` only. Never copy Gadgetbridge code (AGPL).
- Never write to the band unless the packet is verified in the spec. Safe order: read-only, then time, then weather.
- Never unpair, reset or update the firmware of the band.
- Never put the band's serial, address or SEID in code, tests or commits.
- Summarise what changed in plain words after each piece of work.
- Commit to git after each working step. Run builds with xcodebuild and tell me the result.
- Use hyphens, never em dashes.

## Project

A free, open-source, non-profit, **unofficial** iOS companion app for the Sony Wena 3 smartwatch band (BLE name `WNW-21A`), replacing Sony's app now that Sony ended support on 28 Feb 2026. Swift + SwiftUI + CoreBluetooth.

**Read `Docs/` before protocol or feature work:**
- `Docs/wena3-ios-companion-plan.md` - goals, decisions, roadmap (phases), cautions, open questions.
- `Docs/wena3-protocol-spec.md` - BLE wire format (UUIDs, opcodes, byte layouts, activity sync, CRC-16). This is the source of truth for anything sent to the band. Items marked **UNVERIFIED** or "not yet extracted" are not safe to implement as writes.

The owner wants ideas turned into working features end to end (see `~/.claude/CLAUDE.md`); summarise changes in plain words rather than teaching step by step.

## Hard rules

- **Clean-room only.** Implement from `Docs/wena3-protocol-spec.md` and our own captures. Never copy or closely translate Gadgetbridge code (AGPL-3.0); that would conflict with App Store distribution.
- **Never write unverified packets to the band.** Safety order: read-only (device info 1520, battery 1521) -> time/timezone (`0x10`, `0x11` on 1514) -> weather -> settings one packet at a time. Do not send the calendar/notification toggles packet (may disable ANCS notifications, which already work with no app), body properties until verified, Head Linkage (`0xC0`) commands, or anything firmware-related. Firmware flashing is out of scope.
- Never add code that factory-resets the band, unpairs it, or removes its iOS bond - Sony can no longer re-run setup.
- Notifications are delivered by iOS ANCS with no app code; do not implement notification forwarding.
- Branding: avoid "Sony" and "Wena" as the headline app name, keep "unofficial" prominent, no Sony logos/imagery.
- Writing style in docs, comments and UI text: **no em dashes, use hyphens.**

## Build and run

Xcode 27.2. Single project `WenaCompanion.xcodeproj`, app target `MyApp` (display name "Anew Link", formerly "Buckle Link"; the project and folder keep their old "Wena Companion" names, and the Bluetooth restore identifier keeps "BuckleLinkBandCentral", none of which users see) and unit-test target `MyAppTests` (Swift Testing, hosted in the app), both in the shared scheme `MyApp` (`xcshareddata/xcschemes/MyApp.xcscheme`).

```bash
xcodebuild -project WenaCompanion.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build
```

Upload a new TestFlight build (archives Release, build number = git commit count, signs with paid team WVWWUXQ867, bundle ID `com.donut32.anew-link`):

```bash
Scripts/upload-testflight.sh
```

Run all tests (an "iPhone 17" simulator exists on this Mac):

```bash
xcodebuild test -project WenaCompanion.xcodeproj -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

Run one test: add `'-only-testing:MyAppTests/BandInfoParserTests/serialIsSigned()'`. Swift Testing names need the `()`; without it xcodebuild silently runs zero tests and still reports `TEST SUCCEEDED`.

- The simulator has **no Bluetooth**. BLE features must be tested on a real iPhone (Developer Mode on, run from Xcode). Pure logic (CRC-16, Wena timestamp conversion, packet builders/parsers) goes in `nonisolated` types with unit tests in `MyAppTests/`, checked against the spec without a band. Test data must be made up, never the real band's serial.
- New test files placed in `MyAppTests/` join the test target automatically (synchronized folder). In `project.xcproj` the test target uses `"product-type": "bundle.unit-test"`, `"test-host-target": "MyApp"`, plus `TEST_HOST`/`BUNDLE_LOADER` build settings; without those the test bundle fails to link.

## Project configuration notes

- The project file is Xcode 27's JSON-style `project.xcproj`. The `MyApp/` folder is a synchronized folder (`"kind": "folder"`), so new Swift files placed under `MyApp/` join the target automatically - no project file edits needed.
- Build settings that affect code: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (types are main-actor by default; mark BLE/background work `nonisolated` or use actors explicitly), `SWIFT_APPROACHABLE_CONCURRENCY = YES`, Swift language mode 5.0, iOS deployment target 27.2. Info.plist is generated (`GENERATE_INFOPLIST_FILE`), so usage descriptions such as `NSBluetoothAlwaysUsageDescription` and background modes go in as `INFOPLIST_KEY_*` build settings / target capabilities.
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` is on: a file must import every module whose members it uses (for example `import CoreLocation` to read `CLLocation.coordinate`), even if another file already imports it.

## Code structure

- `MyApp/Bluetooth/`: `WenaGATT` (UUIDs), pure `nonisolated` byte code (`BandInfoParser`, `WenaPackets`, `WenaWeather`, `WenaCRC16`, `WenaActivity` with `ActivityStreamAssembler`, `ActivitySummary`), and `BandConnection` (CoreBluetooth). **Every packet write to the band goes through `BandConnection.send(_:to:completion:)`**, one send at a time, and only from a user action, from answering a band request (`BandConnection.onBandRequest`; routed in `AppServices`: type 1 "Get calendar" (hourly) is answered by `MyApp/Calendar/CalendarSync` with `WenaCalendar` entry packets (`0x02`, next 7 days, max 30; EventKit read-only; off-by-default switch that asks calendar access and sends once when switched on, confirmed on the band 9 Nov 2026); type 2 "Locate phone" rings the phone via `MyApp/FindPhone/FindPhone` (no band write; sound with the app open, otherwise a notification; off-by-default switch that asks notification permission); type 11 "Music info" is answered with the `0x05` song text by `MyApp/Music/NowPlayingSync`, which reads Apple Music via `MPMusicPlayerController.systemMusicPlayer` behind its own off-by-default switch; type 3 "Get weather" is answered by `AutoSync.answerWeatherRequest` with time then weather when `WeatherSchedule.shouldAnswerRequest` (at most every 2 h unless the time zone changed; the band also asks after every reconnect); type 0 "Sync tick" (every 30 min), app open and connect all call `ActivityAutoSync.runIfDue`, which syncs activity only every 2 h (`ActivityWindow.isDue`), from `ActivityWindow.start` (last Health save minus 1 h, at most 24 h), and saves to Health with `askPermission: false`, only once steps sharing is already authorised; every tick was judged too often for the band battery) is answered by `ActivityAutoSync`, which runs `syncActivityAndWait(since:)` from `ActivityWindow.start` (last Health save minus 1 h, at most 24 h) and saves to Health with `askPermission: false`, only once steps sharing is already authorised; Health accepts writes while the phone is locked), or from `AutoSync` (`MyApp/Sync/`), which may send only the verified time and weather packets, only while its user switch is on, and only when `WeatherSchedule.isDue` (never sent, new day, over 3 h, or time-zone offset changed) or the band asked. In the background, weather uses `SavedLocation` (the last location, rounded to 2 decimals), because iOS gives no fresh location to a background app with When In Use permission. AutoSync never triggers a permission popup. Alarms (`MyApp/Alarms/AlarmStore`, `WenaAlarms`): three `0x06` packets to 1514 replacing all 9 slots, sent on each user edit; if the band is away the change is marked pending and sent on the next connect (`sendIfPending`). The app list is the source of truth (the band can't be read back). Band settings (`MyApp/Settings/BandSettingsStore`, `BandSettingsView`, packets in `WenaSettings`): vibration `0x08`, disconnect alert `0x09`, do not disturb `0x14`, auto power off `0x15`, day start `0x16`, step goal `0x17`, status page order `0x18`, tool menu order `0x19` (all ids always sent, reordered only), display `0x1A`, home icons `0x1B` (sent after `0x1A`, as Sony does) and buttons `0x1C`, all byte-for-byte from our Sony captures (spec 15); each user change sends only that setting, pending changes go on the next connect, and "Send all settings" sends every one. Never `0x12`, `0x1D` or `0xC0` from there. Notification app list (`MyApp/Notifications/NotificationAppsStore`, `NotificationAppsView`, packets in `WenaNotificationList`, spec 15.3): the whole list then `04`, written to the characteristic after 1514 in 1501 (found by position in `WenaGATT.notificationListCharacteristic`, UUID logged), on each user edit, pending on reconnect, and in "Send all settings"; never followed by `0x12`. Its "Feel it on the band" button sends one test notification to 4002 (`WenaTestNotification`, the section 8 layout Sony's "Try this pattern" uses), only on tap; this is not notification forwarding. The only other writes are Bluetooth subscriptions (`setNotifyValue`): 4002 for the band's requests, kept on while connected and recorded in `BandEventLog` (`MyApp/Diagnostics/`), and 3002 inside `syncActivity` (manual or on the tick), switched off again in `endActivity`. Keep it that way. On an unexpected disconnect, or a failed connect attempt (for example "failed to encrypt the connection" at the edge of range, retried after 2 s), `BandConnection` calls `connect` again (state `.reconnecting`); `stop()` clears `peripheral` first so a deliberate disconnect doesn't reconnect. State restoration is on (`CBCentralManagerOptionRestoreIdentifierKey`, identifier must never change): if iOS closes the app, it keeps the pending connect and relaunches the app in the background, and `willRestoreState` hands the band back to `resume(_:)`.
- Info.plist is generated, but `INFOPLIST_KEY_UIBackgroundModes` is NOT supported, so `UIBackgroundModes` (`bluetooth-central`) lives in `Config/Info.plist`, which Xcode merges via `INFOPLIST_FILE`. Put any other key the `INFOPLIST_KEY_*` settings can't express there, and check the built app's Info.plist with `plutil -p`.
- Extensions of `nonisolated` types (for example `extension WenaPackets`) must also be written `nonisolated extension`, or their members default to the main actor.
- `MyApp/Weather/`: `LocationProvider` (one-shot approximate location), `OpenMeteoClient` (keyless forecast API, coordinates rounded to 2 decimals), and `WeatherSync`, which runs location -> forecast -> packet -> `BandConnection.sendWeather`.
- `MyApp/Health/`: `HealthRecords` (pure, tested: samples -> per-minute records with stable `HKMetadataKeySyncIdentifier`s so re-saving replaces instead of duplicating) and `HealthSync` (write-only HealthKit; never requests read access). The HealthKit entitlement is `Config/MyApp.entitlements` (kept outside `MyApp/` so the synchronized folder doesn't bundle it), set via `CODE_SIGN_ENTITLEMENTS`. HealthKit works with the owner's free Personal Team (confirmed on device, 8 Nov 2026); WeatherKit would not, hence Open-Meteo.
- Debug builds accept `-demoScreen notifications` (or any other name for Band settings) as a launch argument to open one screen with demo data, for simulator checks (`xcrun simctl launch booted com.donut32.anew-link -demoScreen notifications`).
- `MyApp/AppServices.swift` owns the long-lived objects (connection, sync objects) and wires band requests. It's created and started by the `AppDelegate` in `MyApp.swift` at launch, not by a view, because a background relaunch may show no screen. `MyApp/BandStatusView.swift`: `BandStatusView` borrows them; `BandStatusContent` takes plain values so previews need no Bluetooth. Test buttons that send made-up data live under `#if DEBUG` only.

## Protocol essentials (details in the spec)

- Vendor UUIDs: `4EFDxxxx-A6C1-16F0-062F-F196CF496695`. Services 1501 (control 1514, info 1520, state 1521, mode 1503), 4001 (notification char 4002: weather/calendar writes and band-to-phone requests), 3001 (activity char 3002).
- No auth or handshake; the band is already bonded via iOS. Use `retrieveConnectedPeripherals` to find it (it shows as non-connectable to scanners while connected to the iPhone). MAC addresses are not needed.
- Little-endian. Wena timestamp = int32 seconds since 2020-01-01 00:00:00 UTC. Always key packet handling on (characteristic, opcode).
- Activity sync requires firmware >= 2.40 (owner's band reports `2.40JP`); parse the 8-byte ASCII firmware name from 1520 and warn on older firmware.
- Band-initiated requests on 4002 (types 0, 1, 3) are the intended way to wake the app in the background via CoreBluetooth state restoration.
- App Store reviewers will not have a band, so a demo mode is planned.
