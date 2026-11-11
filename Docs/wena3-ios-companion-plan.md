# Wena 3 iOS Companion App - Plan

Last updated: 10 November 2026 (status, pairing design, test backlog and next steps in section 14)

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
- Sony firmware updates did not need Sony's servers once the app was installed: the 2.40JP image is bundled in Sony's Android app 3.20 (`assets/firmware/WN3_231127_240JP.pack`, found 11 Nov 2026, spec 16). It is encrypted, so it can't be modified, only sent as-is over Ambiq's AMOTA. Updating other owners' bands stays **out of scope** and high risk; the owner may experiment on a spare band only.
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
- Can a factory-reset band be set up without Sony's app (needs a second test band to risk)? Research in spec section 14; pairing design in section 14 of this plan.
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
- **Battery (9 Nov):** the band dropped from nearly full to 55% on a heavy test day after syncing activity on every 30-minute tick. The log later showed the tick-based activity sync was not yet installed during most of that drop, so the likelier causes are heavy band use (screen, vibration), many out-of-range reconnects and battery age. Activity now syncs about every 2 hours in the background (on the tick, when 2 h have passed) and band weather requests are answered at most every 2 hours. Measure: one normal day with the app running vs one day force-quit, battery noted morning and evening. **Automatic activity save every 2 hours**: carry the band, lock the phone, then check "Saved activity to Health" lines in the log and band entries in Health.
- **Calendar all-day events**: entries work on the band (confirmed 9 Nov); check an all-day event shows on the right date, and that the hourly request is answered ("Answered calendar request (N events)" in the log).
- **Find my phone vibration** with the app open on silent.
- **Heart rate**: built, untested until the band is worn. Options: Apple Watch lug adapters, a cheap watch head, or the Omega once a good strap fit is found.

**Done since (9 Nov 2026):** find my phone (confirmed on the band), calendar sync (confirmed on the band), calendar, alarm and settings layouts extracted into spec sections 5 and 9, demo mode (checked in the simulator), privacy policy (`Docs/privacy-policy.md`) and release checklist (`Docs/release-checklist.md`).

**Release (9 Nov 2026):** paid Apple Developer Program, bundle ID `com.donut32.anew-link` (team WVWWUXQ867), privacy policy live on GitHub Pages, repo public, build 1.0 (1) on TestFlight and installed on the owner's iPhone. New builds: `Scripts/upload-testflight.sh`.

**Next big topic: pairing a band that lost its bond (assessed 9 Nov 2026, nothing built yet)**

Why it matters: owners who got a new iPhone, tapped "Forget This Device", reset network settings, or factory-reset the band can't use Sony's app to pair again. This is likely the most valuable feature for other owners. The owner's own band is still bonded, so the app has never needed it.

What we know:
- The protocol has no login, challenge or key exchange (spec section 2). Pairing is ordinary OS-level Bluetooth bonding, then plain packets.
- On iOS an app can't pair directly: it connects, and iOS shows its own "Bluetooth Pairing Request" when the app touches an encrypted characteristic. After bonding, the band asks iOS for notifications (ANCS) itself.
- Gadgetbridge pairs Wena 3 on Android without Sony's app, which suggests the band accepts a new phone. Its author reported buggy band-side pairing: after deleting the bond in the band menu, the band spammed pairing requests until rebooted.

What we don't know:
- How the band enters pairing mode (menu, after reset, or by itself when its old phone is gone).
- What a factory-reset band needs before it's usable: possibly a first-time settings sequence (spec section 2), maybe including the `0x12` calendar and notification toggles packet we avoid on bonded bands.
- Whether a band still bonded to an old phone accepts a new one without a reset.

Safety: never test on the owner's band (CLAUDE.md: no unpair or reset). Test with owners who are already stuck (nothing to lose) via an external TestFlight group with a public link (needs Apple's beta review; demo mode and review notes are ready), or a cheap second-hand Wena 3.

Research done 10 Nov 2026: spec section 14. Headlines: Sony's own iPhone setup paired in **iOS Settings > Bluetooth > WNW-21A**, not in the app; the band menu has **Delete pairing** (keeps settings) and **Initialise** (factory reset); Sony required one of them to move to a new phone; "re-setup is impossible" after the shutdown is because Sony's app needs a dead login, not a known band limit; Gadgetbridge pairs without Sony's app; no one has reported pairing a reset band to an iPhone since the shutdown.

### Design: "Pair a band" (10 Nov 2026, not built)

Who it's for: an owner whose band is not bonded to this iPhone (new phone, "Forget This Device", band reset). It never runs for a band that `retrieveConnectedPeripherals` already returns.

Entry: when a connect attempt ends in `.notFound`, the status screen offers "Set up a band that isn't paired yet". Also reachable from the app's settings.

Screens (one step per screen, plain words, a picture of the band menu where it helps):

1. **Before you start.** Charge the band. If an old phone still has the band, switch that phone's Bluetooth off (it grabs the band first). Close Sony's app if it's still installed, and don't use its re-sync or re-pair buttons: they need Sony's login, and what they send to the band is unknown (the owner's Sony app still opens and asks for a re-sync, spec 14.4). It can stay installed. Explain that Anew Link can't do Suica, Alexa or Qrio setup.
2. **Clear the old pairing on the band** (skip if the band was just reset). Band: swipe up > settings > **Delete pairing** > OK. Shown as the normal route because the band keeps its settings and activity. **Initialise** is mentioned only as a last resort behind a "Still not working?" link, with a plain warning: it erases the band's settings and activity history, it can't be undone, and nobody has confirmed yet that a reset band works fully without Sony's app. The app never sends any reset or unpair packet itself.
3. **Clear the old pairing on the iPhone.** Settings > Bluetooth > (i) next to any `WNW-21A` > Forget This Device. A button opens the Settings app.
4. **Pair in iOS Settings** (the Sony-documented route). Settings > Bluetooth > tap `WNW-21A` under Other Devices > Pair (type the code if the band shows one). When it says Connected, **swipe up to go home, don't tap back**, then come back to Anew Link. While this screen is open the app checks `retrieveConnectedPeripherals` every 2 seconds (read-only, no prompt) and moves on by itself when the band appears.
   - Fallback button "Pair from the app instead": scan for `WNW-21A`, connect, read 1520. If the band protects that read, iOS shows its own pairing prompt. Unverified, so it's the second choice; if no prompt appears, the screen sends the user back to Settings.
5. **First-time setup, verified packets only**, sent one at a time through `BandConnection.send` and shown as a checklist: read device info and battery (firmware warning below 2.40), time and time zone (`0x10`, `0x11`), weather (`0x03`, asks location once), calendar entries only if the user switches calendar on, alarms only if the user sets some. Not sent: `0x12`, body properties, display, vibration or any other unverified setting.
6. **Check it works.**
   - Notifications: the app posts one local test notification; ask "Did the band buzz?" This tests ANCS end to end with no band write. iOS may ask "Allow WNW-21A to show notifications?" during pairing: tell the user to tap Allow.
   - Steps: one activity sync; show the step count to compare with the band's own screen.
   - Media buttons: "Try play/pause on the band's music screen".
7. **Done, or what failed.** On any failure: a short list of fixes (move closer, restart the band from its settings menu, repeat steps 2-4) and a "Copy setup report" button that copies the `BandEventLog` lines for this attempt (firmware name, which step failed, battery; never the serial) for the tester to send back.

Build notes:
- Pure state machine (`PairingFlow`, `nonisolated`, unit tested: step order, skip rules, what counts as "found"); the views only render it. The existing scan fallback in `BandConnection.startScan` already finds an advertising band and is reused.
- Demo mode gets a fake run of the whole flow, for App Store review and screenshots.
- No new write types, so the CLAUDE.md write rules are unchanged.

Open questions that only stuck owners can answer (put in the tester notes):
- Does iOS show a plain "Pair" or a code?
- Does a band that only did "Delete pairing" accept the new iPhone, or is "Initialise" needed?
- After "Initialise": do notifications reach the band without `0x12`? Does the band send its 4002 requests (weather, calendar, tick) by itself? If notifications fail on a reset band, `0x12` with both toggles on is the candidate fix, tested only with an owner who opts in and has nothing to lose.
- Does the band spam pairing requests after a reboot (the Gadgetbridge author's bug), and does forgetting it in iOS and pairing once more stop it?

Next: build the flow, then open external TestFlight and invite stuck owners to test it.

### Sony app vs Anew Link (updated 10 Nov 2026, after the Sony captures and the settings screen)

| Sony app feature | Anew Link | What's left |
|---|---|---|
| Sync (time, battery, activity) | Done, automatic: time and weather when the band asks, activity every 2 h in the background | - |
| Weather on the band | Done (Sony's weather service had already ended, so this is better than Sony now) | - |
| Calendar on the band | Done, next 7 days; choose which calendars (built 10 Nov 2026) | - |
| Alarms (9, repeat days, smart wake-up) | Done | Confirm repeat days and smart wake-up on the band |
| Find my phone, song title | Done | - |
| Vibration, display, home icons, button, step goal, day start, do not disturb, auto power off, disconnect alert | Done (settings screen, build 66/67), "Send all settings", "Feel it" test buzz | Confirm each on the band |
| Tool menu order and status page order | Built 10 Nov 2026: drag-to-reorder lists in Band settings, in "Send all settings" (all ids always sent) | Confirm on the band that the new order shows |
| Per-app notifications (which apps reach the band, LED colour, vibration pattern, count) | Built 10 Nov 2026: "Notifications on the band" screen, preset apps plus any name, Calls, "Try it" buzz, in "Send all settings" | Confirm on the band: the list characteristic is found (event log), an app removed from the list stops reaching the band |
| Notifications and calendar master switch (`0x12`) | `12 01 01` sent after every notification list write, as Sony does (owner's OK 10 Nov 2026) | Never `00` in either field |
| Activity history: steps, heart rate | Done, saved to Apple Health | - |
| Sleep, calories, VO2 Max, stress, body energy | Decoded 10 Nov 2026 from our captures (spec 7.1): VO2 Max saved to Apple Health; body energy, stress and calories shown after a manual sync | Sleep is not decoded and won't be checked: the owner doesn't wear the band to sleep (11 Nov 2026), so sleep-related features such as smart wake-up are sent as captured and assumed to work. Calories' unit needs comparing with the band's Calorie screen before saving to Health |
| Body details (birth date, height, weight, gender) | Built 10 Nov 2026: entered by hand in Band settings, sent only once entered | `01` = male confirmed; female `00` is a guess; "Fill in from Apple Health" reads height, weight, birth date and sex (built 10 Nov 2026, owner's OK) |
| Pairing a new or reset band | Not built | Design in plan 14; needs a test on a stuck band |
| Rewrite settings | Done ("Send all settings") | - |
| Watch head (Head Linkage) | Not built | Only for WIRED/Seiko heads, out of scope |
| Account, Suica, Edy, iD/QUICPay, Alexa, Qrio, Riiiver, MAMORIO, firmware | Can't come back | - |

Ways Anew Link can beat Sony's app:
- **Low battery warning on the iPhone** when the band drops to 20% (built 10 Nov 2026, off by default, once per charge). A battery widget (built 11 Nov 2026): Home Screen and Lock Screen sizes, showing the last reading, shared through the App Group `group.com.donut32.anew-link`.
- **Find my band:** a button and a Shortcuts action ("Find My Band", also by Siri) that sends the test notification with the siren pattern, 3 times (built 10 Nov 2026).
- **Focus sync:** a Shortcuts action "Set Band Do Not Disturb" (on or off) for Focus automations (built 10 Nov 2026). On = `14 01 00 00 17 3B` (all day, 00:00-23:59, **UNVERIFIED** that the band treats that as all day); off = the user's own do not disturb setting.
- **Notification list from your phone:** pick from common apps rather than typing names, with sensible defaults for a reset band (built 10 Nov 2026).
- **Home screen preview:** a drawing of the band's home screen that updates as icons are picked.
- **Guided setup** for a new or reset band (plan 14), ending with "Send all settings" and a test buzz.

### Sony app on the owner's iPhone (looked at through iPhone Mirroring, 10 Nov 2026)

Looked at only: no values changed, nothing saved, Sync, Rewrite settings and the watch-head screen not touched.

- **Sony's app still connects and syncs.** The dashboard showed "09:51 sync" for today, while the app was open, with no login. It read steps (against the step goal), battery, calories, VO2 Max, a notification count and heart rate. So opening Sony's app does talk to the band. Whether its automatic sync also writes settings is unknown, so the advice stands: keep it closed.
- **Menu:** Application Settings (Account, App colour theme, Start of day, Sync with Apple Health), Device Settings, Payment Settings, Help, plus user shortcuts.
- **Device Settings list:** Activity, Notification, Vibration, Display, Hardware button, Sleep & Alarm, Disconnection notification, Schedule, Weather, MAMORIO, Alexa, Riiiver, Qrio Lock, Connect watch head, Rewrite settings.
- **Notification settings (new to us):** a master Off/On, then a list of apps plus "Call", each with Notifications on/off, LED colour, vibration pattern (Nothing, Basic, Short, Double, Triple, Rapid, Step up, Step down, Warning, Siren) and number of vibrations, a "Try this notification pattern on wena" button, and "Add an app to notify". Only listed apps reach the band. Since iPhone notifications arrive by ANCS, the band must hold this per-app table itself, keyed by the iOS app. **That packet is not in the spec**: Gadgetbridge never needs it because on Android it sends notifications itself.
- **Vibration:** strength shown as Weak, Medium, Strong (spec `0x08`: 0 normal, 1 weak, 2 strong, so Medium = normal), and "Stop vibrating at rest".
- **Display:** wrist, font size, home screen (left, centre, right icon and Normal or Rich design), tool screen order, status screen order, display time (seconds), raise to wake, language. All in spec `0x1A`/`0x1B`/`0x19`/`0x18`.
  - Tool screen items (10): weather, alarm, timer, find your phone, camera, music, Alexa, Qrio Lock, payment, settings.
  - Status screen items (7): Steps, Heart Rate, Calorie, VO2 Max, Stress & Recovery, Sleep, Body Energy.
- **Hardware button:** long press and double press, each picks an action.
- **Sleep & Alarm:** auto power off (on/off, start, end), alarms, do not disturb (on/off, start, end).
- **Disconnection notification:** on/off and elapsed time in seconds. **Packet not in the spec.**
- **Schedule:** on/off and a tick list of iPhone calendars.
- **Weather:** shows "support for this feature has ended" (Japanese).
- **Start of day:** a time (hour). Spec `0x16`.

The owner's current band settings, to send unchanged the first time Anew Link writes each setting (so nothing visibly changes): vibration Medium, stop at rest off; left wrist, normal font, display 7 s, raise to wake on, English; home icons Stress & Recovery / Heart Rate / Steps, Normal design; long press = weather screen, double press = timer screen; auto power off off (22:00-08:00); disconnect alert off (5 s); day start 0:00; step goal 6000 with goal notification on. Body details are left out of this public doc.

**Captured (10 Nov 2026):** the owner tapped Rewrite settings in Sony's app while PacketLogger recorded the iPhone's Bluetooth. Every settings packet Sony sends is now in spec section 15, including two that Gadgetbridge never had: the per-app notification list (a new characteristic next to 1514) and a `0x09` packet that is most likely the disconnect alert. `0x1A` display, `0x1B` home icons, `0x1C` buttons, `0x17` step goal, `0x08` vibration and `0x16` day start match Sony's values field by field. Sony's app sends `12 01 01` on every rewrite, so sending that exact packet is low risk (lifting the "never `0x12`" rule is still the owner's call). The rewrite also replaced the band's alarms with Sony's list (06:30 every day, the rest empty), so re-save alarms in Anew Link if they differ.

**Next steps, in order:**
1. Test alarms on the band: one alarm 2-3 minutes ahead first, then repeat days and smart wake-up.
2. Band settings screen built 10 Nov 2026 (vibration, display, home icons, button, step goal, day start, do not disturb, auto power off, disconnect alert, plus "Send all settings"), checked in unit tests and the simulator demo. Result on the band: pending. Test on the band one setting at a time, starting with vibration strength and the long-press action, then compare with the band's own settings screens. Not built yet: menu and status page order, per-app notification list.
3. Done 10 Nov 2026 (spec 15.5): button, home icon, menu, status page, colour, pattern and count ids, plus the disconnect alert, all mapped from a second capture. Still open: decoding the other activity types (VO2, stress, body energy, calories, sleep) against Sony's dashboard values, and the vibration pattern "Short" (`01` or `09`).
4. Release: external TestFlight testers (other Wena owners, needs a short beta review), then the App Store listing (`Docs/release-checklist.md`).

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
