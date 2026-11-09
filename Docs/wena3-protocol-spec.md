# Sony Wena 3 BLE protocol notes (draft v0.1)

Working document for the iOS companion app. Written as a description of wire behaviour (byte layouts, UUIDs, sequences), not as a translation of code.

## 0. Provenance and licence notes

- Source studied: Gadgetbridge Wena 3 support (PR #3311 by the original author, merged Sept 2023), read from the GitHub mirror at commit `a0948ee` (22 Dec 2024). We could not read Codeberg source directly (the session's network policy blocks git access to codeberg.org), so on 7 Nov 2026 we checked release notes and the project website instead (see section 11). Treat the byte-level details as accurate for that mirror snapshot only, and re-check them against Codeberg master before shipping.
- Gadgetbridge is AGPL-3.0. This file records interoperability facts (identifiers, byte offsets, ordering). If code is later copied or closely translated rather than written from this spec, AGPL applies to that code.
- Everything here is "as Gadgetbridge does it on Android". Items marked **UNVERIFIED** have not been observed on a real band by us.
- Rule for the build: implement from this document and from our own captures, and ask the original author (GitHub/Codeberg user vladkorotnev, "akasaka / Genjitsu Labs") for confirmation or permission where we are unsure.

## 1. Device identity and GATT layout

- Advertised name: `WNW-21A`. Gadgetbridge matches on name only. The author tried matching on the service UUID and noted it was unreliable on Android at the time.
- Vendor UUID pattern: `4EFD` + 4 hex digits + `-A6C1-16F0-062F-F196CF496695`. Short ids below slot into that pattern.

| Short id | Role | How Gadgetbridge uses it |
|---|---|---|
| 1501 | Common service | Container |
| 1503 | Mode characteristic | Subscribed for notifications. Contents never parsed. **UNVERIFIED** purpose |
| 1514 | Control characteristic | Write: all device settings. Subscribed for notifications but nothing is parsed |
| 1520 | Info characteristic | Read: firmware name and serial. Also subscribed |
| 1521 | State characteristic | Read and notify: battery level |
| 4001 | Notification service | Container |
| 4002 | Notification characteristic | Write: weather, music text, calendar, notifications. Notify: band-to-phone requests (section 6) |
| 3001 | Activity log service | Container |
| 3002 | Activity log characteristic | Write: sync requests. Notify: activity data stream (section 7) |

Also present on the band: a standard HID profile (volume, camera and media buttons). On Android, users have reported needing to connect it separately in system Bluetooth settings before music controls work. On iPhone the equivalent behaviour is unknown.

## 2. Connection sequence used by Gadgetbridge

1. Connect, discover services.
2. Send all settings on 1514, in this order: time, camera app type, menu icons, status pages, display, do-not-disturb, auto power off, vibration, home screen icons, body properties and step goal, day start hour, button actions, calendar and notification toggles.
3. Send calendar events on 4002 (or an "empty" entry if disabled).
4. Read 1521 (battery).
5. Subscribe to 1521, 1514, 1520, 1503, 4002 and 3002.
6. Read 1520 (firmware and serial).
7. Start an activity sync (section 7).

Key findings for iOS:
- **No authentication, challenge or key exchange appears anywhere.** The protocol layer is plain writes and reads once the link is bonded.
- **The MAC address is not used in the protocol.** Gadgetbridge only uses the address as a key for its own local preference storage. CoreBluetooth hiding the MAC is therefore not a blocker.
- Bonding is done by the OS. The original author notes the band's own pairing code is buggy: after unpairing and deleting the bond from the band menu, a reboot made the band spam the phone with pairing requests. Also, Gadgetbridge does not send any "unpair" message when a device is removed (the author flagged this as a gap).

## 3. Encoding conventions

- Multi-byte integers are little-endian.
- Wena timestamp: signed 32-bit count of seconds since 2020-01-01 00:00:00 UTC.
- Packets sent to the band start with a 1-byte opcode. The same opcode value can mean different things on different characteristics, so always key on (characteristic, opcode).

## 4. Time and device status

**Set time** (write to 1514), 5 bytes: `0x10`, then the Wena timestamp (int32).

**Set time zone** (write to 1514), 3 bytes: `0x11`, signed hour offset (1 byte), minute offset (1 byte). For zones with negative offsets the code simply truncates the integer division, so check negative half-hour zones on hardware. **UNVERIFIED** for negative non-whole-hour zones.

**Device info** (read 1520): first 8 bytes are an ASCII firmware name, then an int32 serial number.

**Battery** (read or notify on 1521): byte 0 is the percentage (treated as a signed byte, so values are 0 to 100). Gadgetbridge ignores any further bytes. Whether charging state is encoded is **UNVERIFIED**.

**Body properties** (write to 1514), 10 bytes: `0x1D`, gender (1 byte, enum index; ordering **UNVERIFIED**), birth year (int16), birth month (1 byte), birth day (1 byte), height (int16, centimetres multiplied by 10), weight (int16, kilograms multiplied by 10). History: during the original PR the author reported that calorie counting stopped working, and that entering a height of 19 and a weight of 10 made it work again. Upstream later committed two fixes with the titles "Height and weight were swapped around" and "BodyPropertiesSetting: height then weight on the wire, not the other way around". That explains the odd symptom (the two fields were being sent in the wrong order), so the x10 scaling is probably fine and the order above (height first, then weight) is the corrected one. We have not verified this on a band, so still treat this packet as risky until tested, and do not write it until the rest of the connection is proven.

## 5. Weather, music and calendar (all written to 4002)

**Weather**, 21 bytes: `0x03`, then five days of 4 bytes each (today first, then four forecast days):
1. day condition byte
2. night condition byte
3. minimum temperature + 100
4. maximum temperature + 100

Condition byte = (main condition index << 3) | sub condition index. Condition indexes: 0 sunny, 1 cloudy, 2 rain, 3 heavy rain, 4 snow. The temperature is sent in Fahrenheit, rounded, then offset by 100 (the code's own comment says the band shows Celsius but takes Fahrenheit on the wire). Gadgetbridge sets main and sub equal for clear, rain, heavy rain, snow and full cloud, uses sunny plus cloudy for partly cloudy and haze or mist, and rain plus snow for sleet. It uses the same value for day and night. Gadgetbridge only sends the weather if at least four forecast days exist.

Mapping source is OpenWeatherMap condition codes. For WeatherKit we will need our own mapping onto the five condition types.

Worth knowing from Gadgetbridge issue #4417 (still open, firmware 2.40JP): an owner saw the band show 25 C and snow when it was about 14 C and raining. The phone-side dump in that issue had a current temperature of 288 K (about 15 C), a daily maximum of 298 K (about 25 C) and a condition code for snow. Our reading (an inference, not confirmed by anyone on the thread) is that the weather source reported the wrong condition, and that the band shows the day's maximum because the packet carries only a minimum and maximum per day, with no current-temperature field. So for the iOS app: send accurate daily min and max, expect the band to display the maximum, and do not promise a live current temperature.

**Music text**: `0x05`, length (1 byte, number of UTF-8 bytes that follow), then the text. Text is "Track / Artist", trimmed and truncated to 99 characters. Empty string clears the display. Author's note: Gadgetbridge clears the text on pause, which makes the title vanish on a brief pause. This is a design choice we can improve. Not relevant on iOS in practice (no access to other apps' now-playing data), listed for completeness.

**Calendar entries**: opcode and layout **not yet extracted**. Gadgetbridge sends up to 255 entries, each with start, end, all-day flag, title, location, index and total count, or a special "empty" entry when disabled.

## 6. Requests the band sends to the phone (notify on 4002)

First byte is the request type.

| Value | Meaning | Gadgetbridge behaviour |
|---|---|---|
| 0 | Background sync tick (likely a timer) | Starts an activity sync if the user setting allows |
| 1 | Get calendar | Re-sends calendar |
| 2 | Locate phone | Triggers find-my-phone |
| 3 | Get weather | **Not handled** by Gadgetbridge. **Confirmed on our band** (section 13): sent about every 4 hours |
| 4 | Riiiver side button | Ignored |
| 5 | Riiiver home icon tapped | Ignored |
| 6 | Unknown, possibly payment related | Ignored |
| 10 | Remove notification (followed by int32 notification id) | Ignored |
| 11 | Music info fetch | Sends the current track if playing |

Why this matters on iOS: types 0, 1 and 3 are the band prompting the phone. If the band keeps sending them, they can wake the app through CoreBluetooth background modes and state restoration, which is the most reliable path for time, weather and activity updates.

## 7. Activity sync

Everything flows over 3002. Note: this stream only decodes as described below on firmware 2.40 or later. Older firmware sends packets that do not match (see section 11).

**Phone to band, 3 writes in this order:**
1. Request A, 17 bytes: `0x01`, then four int32 "last sync" timestamps in this order: steps, heart rate, behaviour, VO2.
2. Request B, 17 bytes: `0x02`, then four int32 timestamps in this order: stress, body energy, calories, events.
3. Start, 1 byte: `0xFF`.

A timestamp of 0 means "send everything you have". Otherwise the band sends only data newer than that time per type. Gadgetbridge stores the latest sample time per type in its database and sends those. A fresh install syncs everything.

**Band to phone, notify stream on 3002**, each packet:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | Sequence number. `0xFF` marks the first packet of a sync, then counts 0, 1, 2 ... up to 0x7F, wrapping to 0 |
| 1 | 2 | CRC-16 (little-endian) |
| 3 | 1 | Packet kind: 0 header, 1 data, 2 finish |
| 4 | n | Payload |

- The CRC covers the kind byte plus the payload. Algorithm: standard CRC-16, polynomial 0x8005, MSB-first (no reflection), initial value 0xFFFF, no final XOR. We confirmed that the lookup table in Gadgetbridge equals the table generated from that polynomial.
- The packet with sequence `0xFF` is also a real packet (it carries data) and the receiver expects sequence 0 next.
- On a sequence gap, Gadgetbridge saves what it already has for the current data type and then ignores everything until the next packet with sequence `0xFF` (the next sync). No acknowledgement or retry packet is sent to the band that we could find. Our app should detect gaps and simply restart the sync.
- Packets with a bad CRC are dropped.

**Header payload**: data type (1 byte), then usually a start timestamp (int32).

Data types: 0 steps, 1 heart rate, 2 behaviour (activity kind with a time range), 3 VO2, 4 stress, 5 body energy, 6 calories, 7 unknown.

**Data payloads**:
- Steps and heart rate: one unsigned byte per sample, one sample per minute, starting at the header timestamp. Heart rate of 0 presumably means no reading. **UNVERIFIED**
- Behaviour, VO2, stress, energy and calories layouts: **not yet extracted**. Read the matching parser files next.

Known data quality issues from the author and issue tracker: sleep data is flaky, VO2 stopped reporting on the author's band at one point, and an early version had a bug (caught in PR review) where multiple VO2 samples with the same timestamp overwrote each other in its database. Our own storage should not key samples by timestamp alone for data types that can repeat.

## 8. Notification packets (reference only)

On iPhone the band should get notifications through ANCS with no app involved, so we do not plan to send these. For reference, an app-notification write to 4002 starts with marker `0x00`, then LED colour index, vibration flags, vibration pattern index, vibration count (max 4), title length, message length, flags, kind index, action label length, an int32 notification id, an int32 timestamp, and then the title, message and action label as UTF-8. Limits: 31 characters title, 239 message, 15 action label. A removal packet exists with kind and id.

**Risk to check before writing any settings from iOS:** one settings packet carries "calendar enabled" and "notifications enabled" toggles. If those toggles also gate the band's ANCS handling, writing them wrongly could switch off the notifications that already work. Do not send that packet until we understand it on hardware.

## 9. Not yet extracted (next reads)

Settings opcodes and layouts for: display, do-not-disturb, auto power off, vibration, home screen icons, menu icons, status pages, alarms (9 slots), step goal, day start hour, button actions, camera app type, calendar and notification toggles. Plus the calendar entry packet and the behaviour, VO2, stress, energy and calories parsers.

## 10. Safe verification plan (read-only first)

1. With a BLE explorer app on the iPhone (for example nRF Connect), connect to the already-bonded band and record the service and characteristic list with properties. This only reads, it changes nothing. Compare against section 1.
2. Read 1520 and 1521 and compare with section 4.
3. Subscribe to 4002 and 3002 and see which request types the band sends by itself (settles the GET_WEATHER question).
4. Only after steps 1 to 3, write a time packet, which is the lowest-risk write (the band re-syncs time on connect anyway).
5. Next, weather. Then settings, one packet at a time, avoiding the notification toggles packet and anything about firmware.

Do not factory reset the band or remove its iPhone bond while testing.

## 11. Upstream drift check (7 Nov 2026)

What we could confirm without reading Codeberg source:

- Latest Gadgetbridge release is 2026.11.0 (3 Nov 2026). Releases from 0.91.0 through 2026.11.0 have no Wena entries in the release notes we could read.
- Wena entries found in release notes: initial support in 0.77.0, and "enable body energy" in 0.88.0. Releases 0.78 to 0.90 (other than 0.88) were not checked individually.
- The GitHub mirror's changelog stops at 0.83.0, so the source copy this spec is based on predates later upstream work.

New or changed information on the project's Wena 3 page that is NOT reflected in sections 1 to 10:

- **Activity data transfer requires firmware 2.40** (Gadgetbridge issue #4079, now read in full, closed June 2025). On older firmware (reports of 1.02JP, 1.2 and 2.30JP) the activity stream arrived as packets that do not match the format in section 7, so nothing synced (no steps, no heart rate). Updating the band to 2.40 fixed it for three separate owners, and Sony's own changelog for 2.40 says it fixes activity data transfer. The conclusion on the thread was a band firmware bug, not a protocol change, so section 7 should hold for 2.40 and later. Reported side effect on old firmware: the screen timeout setting did not work either, and it did after updating. Notifications and alarms worked on all versions.
  - **Implication for our app:** parse the firmware name from characteristic 1520 (reports show names like `1.02JP`, `2.30JP`, `2.40JP`, so a leading major.minor number looks parseable, **UNVERIFIED** on our band) and warn if it is older than 2.40, rather than silently showing empty activity data. Do not treat malformed activity packets as a bug in our own code until the firmware is checked.
  - **Community risk:** firmware updates were done through Sony's app, and Sony's login and services have ended. Owners on old firmware may be stuck without activity sync. A commenter asked whether anyone has updated firmware since the login site went down.
  - **Firmware update memo from the thread (not verified by us):** the update file is a `.pack` file bundled inside Sony's Android app and is sent to the band as-is, with no server needed once the app is installed. It appears to use Ambiq's AMOTA over-the-air protocol, and Ambiq publishes an iOS update app. This is a possible future feature, but it is high risk (a bad flash could brick the band) and is out of scope for the first release.
- After the band has been out of range for a long time, the HID connection may need reconnecting in Android settings or camera and music controls stop working (relevant to how we handle reconnects on iOS).
- Body energy sync is now listed as supported (data type 5 in section 7).
- Seiko head linkage is explicitly unsupported (alongside IC/iD/QUICPay, Alexa, Qrio, Mamorio, Riiiver and firmware update).
- Still listed as known issues: flaky sleep data (#3338), non-ASCII notifications sometimes failing (#3359), and higher battery drain than the official app.

### Codeberg review (7 Nov 2026, through the built-in browser)

Commit history for the Wena 3 service folder on master (18,751 commits in the repository overall; the page did not show dates):
- Wena-specific commits are the original support (PR #3311) and four small commits by its author titled as bug fixes: the height and weight order fix described in section 4, "Don't hide music title when momentarily pausing and resuming", and a lint fix.
- Everything newer touching that folder, going by the commit titles, is general framework work rather than Wena protocol work: conversion of the shared data classes to Kotlin, weather model refactors and multiple weather locations, BLE queue and transaction method renames, safer GATT callbacks, locale-safe case conversion (including enum serialisation), a shared temperature-conversion utility, generated sample providers, and a date-of-birth change that adds month and day.
- We could only read titles, not diffs, so a subtle change (for example in the temperature conversion used for weather) is not ruled out. When the Mac clone exists, diff the Wena folders against the mirror snapshot `a0948ee` to be sure.

Wena-related issues we found (search on Codeberg is unreliable, so this list is not exhaustive):
- #4079 (closed): activity transfer failing on old firmware, fixed by firmware 2.40 (details above).
- #4417 (open): wrong weather on the band (see section 5).
- #6428 (open, July 2026, Gadgetbridge 0.91.1 and 0.92.2): music title does not update automatically and the band's media buttons do nothing, on Android 16 with a Sony music app. This is about Android notification and media session plumbing, so it is not relevant to the iOS app.
- #6643 (open, Aug 2026): a detailed, hardware-tested write-up of Seiko/WIRED Head Linkage commands (section 12). The Gadgetbridge maintainer replied that he would try implementing it, so upstream Wena code is likely to change again soon.
- Earlier known issues #3338 (sleep) and #3359 (non-ASCII notifications) were not re-read.

Useful side effect for our plan: the author of #6643 verified every command by sending the raw bytes manually with nRF Connect, which is exactly the safe, app-free method planned in section 10.

Codeberg intermittently returned gateway timeouts during this review, so some pages needed a retry.

Next action: record the band's own firmware name from characteristic 1520, and clone the repository on the development Mac to diff the Wena folders against `a0948ee`.

## 12. Seiko/WIRED Head Linkage (third-party report, not tested by us)

Source: Gadgetbridge issue #6643, written by an owner of a Wena 3 with a WIRED/Seiko N857 watch head, who says every command below was sent by hand with nRF Connect and verified on their hardware, and that the feature still works locally after Sony's shutdown. Only relevant if the owner has a compatible watch head, so it is out of scope for the first release, but it shows how much of the band still works without Sony's servers.

All commands are writes (with response) to the control characteristic 1514, using a first byte of `0xC0` rather than the settings opcodes in section 4.

| Bytes (hex) | Meaning |
|---|---|
| `C0 00 01` | Enable Head Linkage. A "Connect watch head" item then appears in the band's menu and the head is paired from the band itself |
| `C0 20 XX 00 00 00 00 00 00 00 00` | Choose what the head's indicator hand shows. XX: 00 off, 01 band battery, 02 step goal percentage, 03 body energy, 04 heart rate, 05 stress, 06 Suica balance, 07 Edy balance. Can be changed while paired |
| `C0 11 00 AA BB` | Head button A, short press, action AABB |
| `C0 11 01 AA BB` | Head button A, long press |
| `C0 10 00 AA BB` | Head button B, short press |
| `C0 10 01 AA BB` | Head button B, long press |
| `C0 30 02 01` | Show notifications using the watch hands |

Action values (AABB): 0000 none, 0300 find phone, 0400 toggle NFC, 0500 toggle silent or do-not-disturb, 0600 timer screen, 0601 start or stop timer, 0700 weather screen, 0900 calendar screen, 0A00 activity screen, 0B00 notifications screen, 0E00 alarm screen, 1000 music screen, 1001 music play or pause, 1002 next track, 1003 previous track. Alexa, Qrio, wena Pay, Suica, Edy and Riiiver actions also exist but are obsolete without Sony's services.

Defaults the reporter observed: A short = start or stop timer, A long = timer screen, B short = weather screen, B long = Alexa screen.

Sequence the reporter used to enable and pair: enable, indicator, the four button mappings, the notification-hands packet, then put the head into pairing mode and pair from the band's menu.

Caution for us: these share the control characteristic with the settings in section 4. Do not experiment with them unless the owner actually has a compatible head, and treat any write we do not understand as potentially changing band behaviour.

## 13. Confirmed on our band (8 Nov 2026)

Tested with our app (then called Buckle Link, now Anew Link) (commit `2c67349`, read-only screen) on an iPhone 17 Pro, with the owner's band already bonded to that iPhone. No writes, no subscriptions, no pairing changes.

- **Finding the band:** `retrieveConnectedPeripherals(withServices:)` with service 1501 returns the bonded band. The scan fallback was not needed. Connecting from the app caused **no pairing prompt**.
- **GATT layout:** service 1501 with characteristics 1520 and 1521 exists as in section 1, and both can be read.
- **Device info (1520):** layout in section 4 confirmed. Bytes 0-7 decode to the ASCII firmware name `2.40JP` (matches the band's own screen), and bytes 8-11 as a little-endian int32 give a plausible serial number. The serial is deliberately not recorded here.
- **Battery (1521):** byte 0 read as 66%, a plausible value. Not yet compared closely with the band's own display. Whether further bytes encode charging state is still **UNVERIFIED**.
- **ANCS unaffected:** iPhone notifications still reach the band after the app connected, read and disconnected.

- **Time sync (first write, commit `565c595`):** set time (`0x10`) and set time zone (`0x11`, +10:30 or +11:00 local) written to 1514 one after the other, user-triggered. The band **accepted both writes with no error** and stayed connected. Notifications kept working.
  - **Effect not yet observed.** The Wena 3 band has no clock display (the watch head shows the time), so neither a normal sync nor the debug "+5 min" test can be seen on the band. Treat the timestamp encoding as accepted but not yet proven. Verify it through activity-sync timestamps (section 7) or an alarm firing on time, once those are implemented.
  - There is no known way to set the time on the band itself, so the phone app is the only way to correct the band's clock.

- **Weather (commit `aa83cfb`): confirmed working.** The 21-byte `0x03` packet from section 5, written to 4002, with a 5-day forecast from Open-Meteo plus a debug test pattern. The band had shown no weather since Sony's service ended, so the data on screen came from our app.
  - The band shows **all 5 days**, today first (Sunday to Thursday when sent on a Sunday).
  - The condition icons matched for each day of the test pattern (sunny, cloudy, rain, heavy rain, snow), which confirms the `(main << 3) | sub` encoding and indexes 0-4.
  - Temperatures display in **Celsius** with Fahrenheit + 100 on the wire, as section 5 says. Which of min or max the band shows, and the exact per-day values, were not separately checked.
  - The write was accepted on 4002 without subscribing to it first. Notifications kept working.

- **Activity sync (commit `bdf6580`): confirmed working for steps.** We subscribed to 3002, wrote request A (steps and heart rate "since 24 hours ago", the other two types "since now"), request B (all four "since now") and start `0xFF`, then unsubscribed afterwards.
  - The band sent **5 packets, all with valid CRC-16, ending with a finish packet**. That confirms the sequence, CRC algorithm, kind byte and header layout in section 7 on firmware 2.40JP.
  - Step samples decoded to 48 steps, which **matches the band's own step screen**.
  - **Clock proven:** the newest sample was stamped 6:12 pm local time for a sync at 6:13 pm. So the band's clock (set by our `0x10`/`0x11` time sync, after the +5 min test) is right, and activity timestamps are Wena timestamps in **UTC**, shown in local time once decoded.
  - **No heart-rate samples** came back (either none sent, or all zero, which we skip as "no reading"). The band had not been worn, so there was no heart rate to record. Heart-rate decoding is still unverified: re-test after wearing the band.
  - "Since now" for the six undecoded types worked as hoped: nothing extra was streamed. Notifications kept working.

- **Media buttons and camera shutter (no app involved), 8 Nov 2026:** over the band's existing iOS Bluetooth pairing, the band's music screen controls Apple Music play/pause, next, previous and volume, and the band's "open camera" action sends a volume-key press. That **takes a photo in the iPhone Camera app** and changes the volume anywhere else. This answers the "unknown on iPhone" note in section 1: the media-button profile works on iOS with no companion app. These presses go straight to iOS and **never appear on 4002**, so our app can't see them. Alexa actions produce nothing, since that service ran through Sony's and Amazon's servers.

- **Band requests on 4002 (commit `656ee78`, first observations):** subscribing to 4002 works, and the band sends requests to the app. **Type 11 "Music info" is confirmed**: it arrived when the band's music screen was opened (2 requests seen). This is the trigger for sending the `0x05` track text. How often the other types arrive (especially type 0 sync tick and type 3 get weather) is waiting on a longer log.

- **Music text `0x05` (commit `017792b`): confirmed working** as the answer to a type 11 request. "Song / Artist" from Apple Music appears on the band's music screen as a **scrolling line**. A `0x05` sent unprompted before the screen was opened (debug test, no request answered) was **not** shown, which suggests the band displays the text it gets in answer to its own request when the screen opens. Skipping tracks updates the title, and it keeps working **with the iPhone locked**: iOS wakes the app in the background (Bluetooth background mode) for each type 11 request. This proves band-initiated background wake-ups work, which the automatic background sync design will build on.

- **Band request schedule (overnight log, 8-9 Nov 2026, phone locked, band in the same room):** only types 0, 1 and 3 arrive by themselves.
  - **Type 0 sync tick: every 30 minutes**, all night. The timer restarts when the band reconnects (ticks moved from :08:58/:38:58 to :14:17/:44:17).
  - **Type 1 get calendar: hourly**, 20 seconds after every second tick.
  - **Type 3 get weather: about every 4 hours** (01:14:42, 05:14:41), 5 seconds after a calendar request. Once it also came straight after a reconnect (20:44), but not after another (22:32).
  - Two "connection has timed out" disconnects were the phone being taken out of range. The app's pending reconnect waited about 1 h 43 min and reconnected by itself; the connection then held from 22:32 to past 05:14.
  - Answering type 3 with the `0x03` weather packet (and time first) is how Anew Link now keeps weather fresh in the background. **Confirmed, 9 Nov 2026 (commit `20bf88d`):** 4 requests, each answered within 2-9 seconds, including with the phone locked.
  - **The band also sends get calendar and get weather straight after (almost) every reconnect** (06:11, 07:11, 07:15, 07:25 on 9 Nov).
  - **Gap without state restoration:** from 08:12 to 13:47 on 9 Nov the app stayed "Reconnecting" although the band was in range (notifications and calls reached it over iOS's own link). iOS had most likely closed the app, ending its pending connect. State restoration was added next to fix this.
  - **State restoration confirmed, 9 Nov 2026 (commits `ca6f74a`, `7cffd77`):** after the app was stopped from Xcode, iOS relaunched it in the background when the band went out of range (14:10:49 and 14:36:11, "Restored by iOS in the background" logged with the disconnect), and it reconnected with no screen shown (14:11:00).
  - **Find my phone (type 2):** the app answers by ringing the phone (sound with the app open, notification otherwise). It sends nothing back to the band. **Confirmed, 9 Nov 2026 (commit `a7ac278`):** each press of find phone on the band sends one type 2 request; with the switch on, the app rang with sound when open (17:49:36) and showed the notification within a second when in the background (17:49:41, 17:49:52). The phone was on silent, so the notification was silent as expected. With the app open on silent, no chime was heard (the sound follows the media volume), so vibration while ringing was added next.
  - **Failed connect attempts at the edge of range:** iOS can report "Failed to encrypt the connection" for a pending reconnect. The app used to give up there, which likely caused the 08:12-13:47 gap. Since commit `6f8edc7` it retries after 2 s: confirmed at 15:52:06, reconnected 39 s later and answered the weather request.

Still open from section 10: subscribing to 4002 and 3002 to see which requests the band sends by itself (this writes the subscription descriptor, so it is the next step up from pure reads).
