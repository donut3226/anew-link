# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About this project

Free, open-source, non-profit iOS companion app for the Sony Wena 3 band, built by a beginner as a first app. Swift, SwiftUI, CoreBluetooth. Read `Docs/` first (the plan and the protocol spec).

## Rules

- Clean-room: implement from `Docs/wena3-protocol-spec.md` only. Never copy Gadgetbridge code (AGPL).
- Never write to the band unless the packet is verified in the spec. Safe order: read-only, then time, then weather.
- Never unpair, reset or update the firmware of the band.
- Never put the band's serial, address or SEID in code, tests or commits.
- Explain Swift and Xcode concepts in plain words as you go, and make small steps.
- Commit to git after each working step. Run builds with xcodebuild and tell me the result.
- Use hyphens, never em dashes.

## Project

A free, open-source, non-profit, **unofficial** iOS companion app for the Sony Wena 3 smartwatch band (BLE name `WNW-21A`), replacing Sony's app now that Sony ended support on 28 Feb 2026. Swift + SwiftUI + CoreBluetooth.

**Read `Docs/` before protocol or feature work:**
- `Docs/wena3-ios-companion-plan.md` - goals, decisions, roadmap (phases), cautions, open questions.
- `Docs/wena3-protocol-spec.md` - BLE wire format (UUIDs, opcodes, byte layouts, activity sync, CRC-16). This is the source of truth for anything sent to the band. Items marked **UNVERIFIED** or "not yet extracted" are not safe to implement as writes.

The owner is a first-time iOS developer: **explain Swift/SwiftUI/iOS concepts as you go.**

## Hard rules

- **Clean-room only.** Implement from `Docs/wena3-protocol-spec.md` and our own captures. Never copy or closely translate Gadgetbridge code (AGPL-3.0); that would conflict with App Store distribution.
- **Never write unverified packets to the band.** Safety order: read-only (device info 1520, battery 1521) -> time/timezone (`0x10`, `0x11` on 1514) -> weather -> settings one packet at a time. Do not send the calendar/notification toggles packet (may disable ANCS notifications, which already work with no app), body properties until verified, Head Linkage (`0xC0`) commands, or anything firmware-related. Firmware flashing is out of scope.
- Never add code that factory-resets the band, unpairs it, or removes its iOS bond - Sony can no longer re-run setup.
- Notifications are delivered by iOS ANCS with no app code; do not implement notification forwarding.
- Branding: avoid "Sony" and "Wena" as the headline app name, keep "unofficial" prominent, no Sony logos/imagery.
- Writing style in docs, comments and UI text: **no em dashes, use hyphens.**

## Build and run

Xcode 27.2. Single project `WenaCompanion.xcodeproj`, app target `MyApp` (display name "Wena Companion") and unit-test target `MyAppTests` (Swift Testing, hosted in the app), both in the shared scheme `MyApp` (`xcshareddata/xcschemes/MyApp.xcscheme`).

```bash
xcodebuild -project WenaCompanion.xcodeproj -scheme MyApp -destination 'generic/platform=iOS Simulator' build
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
- Current code is the Xcode template (`MyApp/MyApp.swift`, `MyApp/ContentView.swift`).

## Protocol essentials (details in the spec)

- Vendor UUIDs: `4EFDxxxx-A6C1-16F0-062F-F196CF496695`. Services 1501 (control 1514, info 1520, state 1521, mode 1503), 4001 (notification char 4002: weather/calendar writes and band-to-phone requests), 3001 (activity char 3002).
- No auth or handshake; the band is already bonded via iOS. Use `retrieveConnectedPeripherals` to find it (it shows as non-connectable to scanners while connected to the iPhone). MAC addresses are not needed.
- Little-endian. Wena timestamp = int32 seconds since 2020-01-01 00:00:00 UTC. Always key packet handling on (characteristic, opcode).
- Activity sync requires firmware >= 2.40 (owner's band reports `2.40JP`); parse the 8-byte ASCII firmware name from 1520 and warn on older firmware.
- Band-initiated requests on 4002 (types 0, 1, 3) are the intended way to wake the app in the background via CoreBluetooth state restoration.
- App Store reviewers will not have a band, so a demo mode is planned.
