# Wena 3 iOS Companion App - Plan

Last updated: 9 November 2026 (status, test backlog and next steps in section 14)

Companion document: `claude/wena3-protocol-spec.md` (the BLE protocol facts extracted from Gadgetbridge). Read it alongside this plan.

## 1. Project goal

Build a free, open-source, non-profit iOS companion app for the Sony Wena 3 smartwatch band, so owners can keep using it now that Sony's app and services have ended. This is also a learning project: the first Xcode and iOS app, built with Claude Code's help the whole way.

## 2. Key facts (verified 7 Nov 2026)

- **Sony ended Wena 3 support and services on 28 February 2026.** App login, app download and updates, new setup from the app, in-app weather settings, repairs, Suica, MAMORIO, Riiiver, Alexa and health-app integrations have all ended. Account data is deleted.
- **What still works on already-set-up bands (owner reports, March 2026):** notifications, step counter, heart rate, call vibration, Qrio Lock. Gone: weather and other cloud features, and any new setup or pairing through the official app (source: tecstaff.jp). Treat the Smartlet page claim that notifications are blocked as a competitor's sales claim that conflicts with owner reports.
- **Trademark and domain** for "wena" moved to augment AI in March 2026 (new "wena X" product). Avoid "Wena" as the headline app name and keep "unofficial" prominent.
- **No iOS replacement project found.** Reddit, X and Japanese forums (5ch, Kakaku.com) could not be searched with my tools, so a manual check is still worth doing.
- **Gadgetbridge (Android, AGPL-3.0, on Codeberg) supports Wena 3** ("Highly supported"). No iPhone version exists.
- **Latest Gadgetbridge release is 2026.11.0 (3 Nov 2026).** Wena entries appear only in 0.77.0 (initial support) and 0.88.0 (body energy). Recent commits touching the Wena folder are framework refactors (titles only reviewed), so the protocol looks stable. The spec was taken from a GitHub mirror at commit a0948ee (22 Dec 2024); a diff against current Codeberg source is still to do on the Mac.

## 3. Protocol summary (details in the spec)

- Vendor UUID pattern `4EFDxxxx-A6C1-16F0-062F-F196CF496695`. Advertised name `WNW-21A`.
- **No authentication or handshake.** The MAC address is not part of the protocol (Gadgetbridge only uses it as a local key), so CoreBluetooth hiding MACs is not a blocker.
- Services: 1501 (mode, control, device info, state and battery), 4001 (weather, music, calendar writes and band-to-phone requests), 3001 (activity log stream).
- Little-endian. Wena timestamps are seconds since 2020-01-01 UTC.
- Weather packet: `0x03` plus 5 days x 4 bytes. The band shows the day maximum, there is no current-temperature field.
- Activity sync: write two request packets then start `0xFF`; stream on 3002 with sequence byte, CRC-16 (poly 0x8005, init 0xFFFF, verified against Gadgetbridge's table), kind byte and payload. Steps and heart rate are 1 byte per minute.
- Not yet extracted: display, DND, alarms, button actions, home and menu pages, calendar entry packet, and parsers for behaviour, VO2, stress, body energy and calories.

## 4. Firmware finding (important)

- **Activity sync needs firmware 2.40** (Gadgetbridge issue #4079). Older firmware sends malformed activity packets, which is a band firmware bug, not an app bug.
- Firmware names look like `1.02JP`, `2.30JP`, `2.40JP`. They can be read from the band (8-byte ASCII name in device info).
- Sony firmware updates needed Sony's servers, which are down. The update path (Ambiq AMOTA, a .pack file inside the Sony Android app) is high risk and **out of scope**.
- **Confirmed 8 Nov 2026: the owner's band reports FW VER 2.40JP on its own screen**, so activity sync should be possible. The band is also visible in nRF Connect as a Sony (company ID 0x012D) advertiser that disappears when the band screen turns off, but it showed as non-connectable with no name, so it may be bonded to or connected with an iPhone.
- So: check the band's firmware first. If it is below 2.40, activity data is off the table and the app focuses on time, weather, settings and calendar.

## 5. ANCS finding: iOS notifications probably already work

On iOS, apps cannot read other apps' notifications. Accessories use **ANCS**: the band bonds in iOS Settings > Bluetooth and subscribes to notifications itself. Sony's pairing flow and help guide match this, and owners report notifications continuing after shutdown. So notifications likely need no app code, only a healthy bond (to verify on the owner's band). Gadgetbridge's notification packet code is reference only.

## 6. What an iOS app would still add

| Feature | Needs app? | Notes |
|---|---|---|
| Notifications | Probably no (ANCS) | Verify. Per-app filtering and LED or vibration settings might need the app |
| Time and timezone sync | Yes | Simple writes (`0x10`, `0x11`); lowest-risk first write |
| Weather | Yes | WeatherKit, or Open-Meteo (keyless) as fallback so no API key ships in an open-source repo |
| Calendar | Yes | EventKit |
| Settings (display, alarms, buttons, pages) | Yes | Needs more spec extraction |
| Activity and health | Yes, firmware 2.40 only | HealthKit |
| Setup of a reset band | Needs testing | Protocol has no handshake, so possibly just iOS bonding plus settings writes |
| Music screen | Dropped | iOS gives apps no now-playing access |
| Firmware and battery info | Yes | Read-only, easy |

## 7. Decisions made

| Topic | Decision |
|---|---|
| Platform | iOS, Swift + SwiftUI, CoreBluetooth |
| Distribution | Free, no ads, non-profit, open source on GitHub, App Store |
| Naming | Avoid "Sony" and "Wena" as headline brand. Chosen 9 Nov 2026: **Anew Link** ("Wena" backwards; "anew" = a new life for the band), formerly Buckle Link. "companion for Wena 3" only as a subtitle |
| Positioning | "Unofficial, open-source companion app for a discontinued device" |
| Assets | No Sony logos or imagery |
| Approach | Minimal first (connect, read info, set time), then one feature at a time |
| Hardware | Personal MacBook Pro, Wena 3 (to be located after the house move), a real iPhone |
| Apple account | Personal Apple Developer account in Xcode > Settings > Accounts |
| Licence path | Clean-room: implement from the spec (interoperability facts only), do not copy Gadgetbridge code. Also ask the author (vladkorotnev, "akasaka / Genjitsu Labs") for permission or dual licence; this removes the AGPL vs App Store tension |

## 8. Cautions

- **Do not factory-reset the band, delete its iOS bond or remove the phone it is paired to.** Sony cannot re-run setup, so a reset band may be stuck.
- **No firmware flashing.** Not in this project.
- **Avoid the notification-toggles packet and any unknown writes.** Writes the spec has not verified can misconfigure the band. Order of safety: read-only first, then time write, then weather, then settings.
- Consider a **second test band** (cheap used unit) before experimenting with risky writes.
- iOS background BLE is restricted. Use state restoration; band-initiated requests on characteristic 4002 can wake the app.
- App Store review: reviewers will not have a Wena 3, so include a **demo mode** and clear review notes.
- Sony-server features (Suica, MAMORIO, Alexa, Riiiver, Qrio, cloud sync) cannot be replicated.
- **Head Linkage commands** (Seiko/WIRED models, Gadgetbridge issue #6643: `0xC0` prefixed writes to the control characteristic) are out of scope for v1; upstream plans to implement them.

## 9. Roadmap

**Phase 0 - Prep and reality check (no code, the band is the first step)**
1. Find the band and charge it.
2. Do not change pairing. Note whether iPhone notifications appear on it.
3. Install **nRF Connect** (iOS) and explore **read-only**: scan, find `WNW-21A`, read device info (1520) to get the **firmware name**, read battery state (1521). Do not write anything yet.
4. Write down the firmware name. If it is below 2.40, drop activity sync from the plan.
5. Decide whether to email the Gadgetbridge author about licensing.
6. Manual search of Reddit, X and Japanese forums for existing iOS efforts.

**Phase 1 - Setup and foundations**
- Install Xcode, create the project (iOS App, SwiftUI, Swift), run in the simulator
- Add the Apple ID in Xcode, run on the real iPhone
- Create the GitHub repo with README and licence
- Learn Swift and SwiftUI basics with Claude Code explaining as you go

**Phase 2 - BLE fundamentals (real iPhone required)**
- CBCentralManager, scanning, connect, discover services
- Use `retrieveConnectedPeripherals` for the already-bonded band
- Read device info and battery; show firmware on screen

**Phase 3 - Protocol, in safe order**
1. Time and timezone sync
2. Weather
3. Calendar
4. Settings (extract remaining formats from the spec first)
5. Activity and HealthKit (only if firmware is 2.40+)
6. Notification settings only if ANCS alone is not enough

**Phase 4 - Polish and release**
- UI polish, demo mode, TestFlight beta with other owners
- Privacy declarations (Bluetooth, calendar, health, location if used)
- App Store submission and open-source release with protocol docs and credit to Gadgetbridge

## 10. Effort estimate

About **4-5 months part-time** for a first-time iOS developer to reach a releasable app (time, weather, calendar, core settings). Activity and HealthKit could add 1-2 months and depend on firmware. The ANCS finding removes notifications from the code scope.

## 11. Getting started with Claude Code (first-timer guide)

Facts checked against the official docs on 7 Nov 2026. Claude Code needs a paid Claude plan (Pro, Max, Team or Enterprise) or a Console account, and macOS 13 or later.

**Two ways to run it. Pick one to begin with:**
- **Desktop app, Code tab (easiest for a first timer):** download the Claude desktop app for Mac, sign in, open the Code tab, choose Local and open your project folder. No terminal or Node.js needed. Shows diffs with approve or decline buttons.
- **Terminal CLI:** open Terminal (Cmd+Space, type Terminal), run `curl -fsSL https://claude.ai/install.sh | bash`, open a new window, check `claude --version`, then `cd` into your project folder and run `claude`. Homebrew alternative: `brew install --cask claude-code`.

You still need **Xcode** for the simulator, signing and running on the iPhone. Claude Code edits files and can build with `xcodebuild`; Xcode is the control room.

**Step by step**
1. Install Xcode from the Mac App Store (large download), open it once to accept the licence.
2. In Xcode: File > New > Project > iOS > App. Interface SwiftUI, Language Swift. Save it in a folder such as `~/Projects/WenaCompanion`.
3. Press Cmd+R to run in the simulator, so you know the baseline works.
4. In that folder, create a git repo (ask Claude Code: "initialise a git repo with a sensible .gitignore for Xcode"). Commit before and after each Claude session so any change can be undone.
5. Put `wena3-ios-companion-plan.md` and `wena3-protocol-spec.md` in a `docs/` folder inside the project.
6. Start Claude Code in the project folder and run `/init` to create `CLAUDE.md`. Then add to it: the project goal, "read docs/ first", "clean-room: never copy Gadgetbridge code", "never write unverified packets to the band", "explain Swift concepts as you go, I am a beginner", and "no em dashes, use hyphens".
7. First prompts, one at a time: "explain the folder structure of this project", then "what does each file do?", then small edits like "change the main screen text".
8. Use **Plan mode** (Shift+Tab cycles modes in the CLI; a Plan option exists in the desktop app) before big tasks, so Claude proposes an approach without editing files. Review each diff while you are learning; do not switch to auto-approve yet.
9. Ask for **tests for pure logic first** (CRC-16, timestamp conversion, weather packet building). These can be checked against the spec with no band, and run in the simulator.
10. BLE needs a **real iPhone** (the simulator has no Bluetooth). Plug the iPhone in, enable Developer Mode on it, pick it as the run destination in Xcode.
11. Build order for the first real session: scan and list nearby devices, connect to `WNW-21A`, read device info and battery, show the firmware name. Only then add the time write.

**Useful habits**
- Be specific: "add a SwiftUI screen listing nearby BLE devices" beats "add Bluetooth".
- Paste Xcode error text straight into Claude Code.
- `/clear` between unrelated tasks; `claude -c` continues the last conversation.
- Commit often; `git checkout` undoes unwanted changes.

## 12. Open questions

- (Answered: firmware 2.40JP.) Band is bonded and connected to the owner's iPhone, which explains why nRF Connect shows it as non-connectable.
- (Answered 8 Nov 2026: yes.) Notifications appear on the band with no companion app, confirming ANCS. Notifications need no app code.
- Does the Gadgetbridge author agree to a licence arrangement, or do we go clean-room only?
- Does current Codeberg source differ from the mirror the spec was built from (diff against a0948ee)?
- Can a factory-reset band be set up without Sony's app (needs a second test band to risk)?
- Final app name?

## 13. Gadgetbridge issues worth knowing

- #4079: activity sync needs firmware 2.40
- #4417: weather shows day maximum, no current-temperature field
- #6428, #3338, #3359: Wena-related reports, titles only reviewed
- #6643: Head Linkage (Seiko/WIRED) commands, out of scope for v1

## 14. Status and next steps (9 Nov 2026)

App: **Anew Link** (formerly Buckle Link), repo `donut3226/anew-link` (private, MIT). Runs on the owner's iPhone 17 Pro from Xcode with a free Personal Team. Details of every hardware result are in spec section 13.

**Working on the real band:**
- Read firmware (2.40JP), serial and battery
- Time sync (proven via activity timestamps)
- 5-day weather from Open-Meteo: answered in the background whenever the band asks (about every 4 hours and after reconnects), using the last saved location; also when the app opens if due (another day, over 3 h old, or time zone changed)
- Step sync and saving to Apple Health (no duplicates)
- Song title from Apple Music on the band's music screen, answered in the background (type 11), including with the phone locked
- Background connection: listening for band requests on 4002 (saved debug log), auto-reconnect including retry after a failed attempt at the edge of range, Bluetooth state restoration (iOS relaunches the app in the background, confirmed)
- No app needed: notifications (ANCS), media buttons, volume, camera shutter
- Name **Anew Link** and app icon "Sunrise clasp", with "Night clasp" for dark home screens and a tinted version (`Design/AppIcon/`)

**Test backlog (built, not yet confirmed on the band):**
- **Automatic activity save on the 30-minute sync tick** (commit `e15e5c4`): wear or carry the band, lock the phone for an hour or two, then check the log for "Saved activity to Health" about every 30 minutes and look for band entries in Health > Steps > Show All Data. Unproven: Health writes with the phone locked (Apple documents that they're held until unlock). Watch for "Weather request not answered: busy" right after a tick.
- **Heart rate**: built, untested until the band is worn. Options: Apple Watch lug adapters, a cheap watch head, or the Omega once a good strap fit is found.

**Next steps, in order:**
1. Remaining spec extraction (calendar, alarms, display and other settings), then calendar sync. The band asks for the calendar hourly (type 1).
2. Phase 4 polish: demo mode for App Review, privacy policy (Health, location, Apple Music), TestFlight.

iOS background refresh as a backup was dropped: the band's own 30-minute tick and 4-hourly weather request already wake the app.

**Known constraints:** force-quitting the app stops background wake-ups until it's opened again; after a reboot, open it once; WeatherKit needs the paid developer program (hence Open-Meteo); payments (Suica, iD, QUICPay) and Alexa can't come back.

## 15. Sources

- Sony Japan service-end notice: https://www.sony.jp/support/smartwatch/info/20241128-service.html
- Sony Japan support page: https://www.sony.jp/support/smartwatch/
- Sony Wena 3 help guide: https://www.sony.jp/support/smartwatch/helpguide_wena3.pdf
- tecstaff post-shutdown check: https://tecstaff.jp/2026-03-02_wena.html
- Gadgetbridge Wena 3 wiki: https://codeberg.org/Freeyourgadget/Gadgetbridge/wiki/Sony-Wena-3
- Gadgetbridge pull request #3311: https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3311
- Gadgetbridge issue #4079: https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/4079
- Gadgetbridge issue #4417: https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/4417
- Gadgetbridge issue #6643: https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/6643
- Gadgetbridge releases: https://codeberg.org/Freeyourgadget/Gadgetbridge/releases
- Gadgetbridge Sony device list: https://gadgetbridge.org/gadgets/wearables/sony/
- Smartwatch Life Japan on Gadgetbridge: https://www.smartwatchlife.jp/82606/
- wena trademark transfer: https://finance.biggo.com/news/UoKyt5wBTwP6zY3HY0Bp
- wena X relaunch: https://note.com/everywhere30/n/n32a3e2b97eb0?hl=en
- Gigazine setup walkthrough: https://www.gigazine.net/news/20201206-wena3/
- ANCS example: https://github.com/k97/WearBridge
- Claude Code quickstart: https://code.claude.com/docs/en/quickstart
- Claude Code terminal guide: https://code.claude.com/docs/en/terminal-guide
- Claude Code desktop quickstart: https://code.claude.com/docs/en/desktop-quickstart
- Your first day in Claude Code: https://support.claude.com/en/articles/14552382-your-first-day-in-claude-code
