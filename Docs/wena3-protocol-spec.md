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

**Body properties** (write to 1514), 10 bytes: `0x1D`, gender (1 byte, enum index; ordering **UNVERIFIED**), birth year (int16), birth month (1 byte), birth day (1 byte), height (int16, centimetres multiplied by 10), weight (int16, kilograms multiplied by 10). History: during the original PR the author reported that calorie counting stopped working, and that entering a height of 19 and a weight of 10 made it work again. Upstream later committed two fixes with the titles "Height and weight were swapped around" and "BodyPropertiesSetting: height then weight on the wire, not the other way around". That explains the odd symptom (the two fields were being sent in the wrong order), so the x10 scaling is probably fine and the order above (height first, then weight) is the corrected one. Sony's own capture (15.2) confirms the 10-byte layout and the height-then-weight order; the values only make sense that way. The sex byte was `01` while Sony's Activity settings screen showed **Male** (seen through iPhone Mirroring the same day), so `01` = male is confirmed. Female is most likely `00` (possibly `02`), **UNVERIFIED**. Anew Link sends it only after the user enters body details, with `01` male and `00` female.

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

**Calendar entries** (extracted 9 Nov 2026 from the mirror snapshot, **UNVERIFIED** on our band): one write to 4002 per event, little-endian, 14 bytes plus the two texts:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | marker `0x02` |
| 1 | 1 | position of this event in the list, **1-based** (1, 2, 3...) |
| 2 | 1 | total number of events in the list |
| 3 | 1 | title length in UTF-8 bytes |
| 4 | 1 | location length in UTF-8 bytes |
| 5 | 1 | all-day flag: 1 = all day, 0 = timed |
| 6 | 4 | start, Wena timestamp (int32) |
| 10 | 4 | end, Wena timestamp (int32) |
| 14 | n | title, UTF-8, no terminator |
| 14+n | m | location, UTF-8, no terminator |

- The whole list is re-sent each time (position 1 of N up to N of N), at most 255 events. Gadgetbridge sends it on connect, on each type 1 "get calendar" request, and whenever the phone's calendar changes.
- **Empty list**: a single 14-byte packet `02 00 00 00 00 00` followed by eight zero bytes (position 0, total 0, no texts, zero times). Gadgetbridge sends this when calendar sync is switched off or there are no events.
- **All-day events**: Gadgetbridge passes Android's all-day times unchanged, and Android stores those at **00:00 UTC** of the event's date (end = start + whole days). So the band most likely expects an all-day event's start at midnight UTC of the calendar date, not local midnight. We follow that.
- Text lengths are single bytes, so each text must be at most 255 bytes. Gadgetbridge does not shorten them; we cap both to stay well inside the band's small screen and the BLE write size.
- Which events and how far ahead are the phone app's choice (Gadgetbridge uses its general calendar sync window).
- The separate settings packet `0x12` (calendar and notification toggles, section 9) is **not** needed to send entries. Our band already asks for the calendar hourly, which suggests its calendar is switched on.

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
- Behaviour, VO2, stress, energy, calories and events: decoded from our own captures of Sony's app, see 7.1.

### 7.1 The other data types, from our captures (10 Nov 2026)

Source: the two PacketLogger captures of Sony's app (section 15), which each ran normal activity syncs (four in all, one covering 8 hours of a day). Decoded by us from the raw stream; no Gadgetbridge code involved. The band was mostly off the wrist that day (steps total 89), so values are few. Sony's requests asked for every type, with each type's own "last sync" time.

| Type | Header | Data layout | What we saw | Status |
|---|---|---|---|---|
| 2 behaviour | type byte only (no time) | 13-byte records: kind (1), then three int32 times: end, start, end again | Back-to-back 16-minute blocks (shorter at the edges). Kind `01` most of the day, `09` in a few blocks (12:42-12:56, 17:14-17:16, 17:56-18:20) | Layout **confirmed** (lengths are exact multiples of 13, times chain). Kind meanings **UNVERIFIED**; no night was captured, so the sleep kinds are unknown. The owner doesn't wear the band to sleep, so this stays open unless a tester shares a morning sync |
| 3 VO2 | type byte only | 5-byte records: int32 date (midnight UTC of the day), uint8 VO2 Max in ml/kg/min | One record, 43, dated the day before; Sony's next request used that date + 60 s as its VO2 "last sync" | Layout **confirmed** by Sony's own request; value plausible, not yet checked against the band's VO2 Max screen |
| 4 stress | type, int32 start | 1 byte per minute | Every minute `7F` (127) | `7F` most likely means "no reading" **UNVERIFIED**; real values not seen yet |
| 5 body energy | type, int32 start | 1 byte per minute, 0-100 | Falls slowly through the day (65 to 38), one step per 10-15 minutes | Looks like the percentage shown on the band, **UNVERIFIED** against the band's screen |
| 6 calories | type, int32 start | uint16 little-endian per minute | Floor of 734 most minutes (band off the wrist), up to 1319 when active | Unit **UNVERIFIED**: if it is 1/1000 kcal (small calories), the floor is a resting 1057 kcal a day, which is plausible. Compare the day's total with the band's Calorie screen before saving to Health |
| 7 events | type byte only | 8-byte records: `07`, int32 time, then 3 bytes (`01 xx 00`, xx seen as 00, 01, 03, 04) | 38 events over 8 hours, clustered | Meaning unknown (maybe screen or button events). Not used |

Steps and heart rate (types 0 and 1) matched section 7 exactly in the same captures.

Known data quality issues from the author and issue tracker: sleep data is flaky, VO2 stopped reporting on the author's band at one point, and an early version had a bug (caught in PR review) where multiple VO2 samples with the same timestamp overwrote each other in its database. Our own storage should not key samples by timestamp alone for data types that can repeat.

## 8. Notification packets (reference only)

On iPhone the band should get notifications through ANCS with no app involved, so we do not plan to send these. For reference, an app-notification write to 4002 starts with marker `0x00`, then LED colour index, vibration flags, vibration pattern index, vibration count (max 4), title length, message length, flags, kind index, action label length, an int32 notification id, an int32 timestamp, and then the title, message and action label as UTF-8. Limits: 31 characters title, 239 message, 15 action label. A removal packet exists with kind and id.

**Risk to check before writing any settings from iOS:** one settings packet carries "calendar enabled" and "notifications enabled" toggles. If those toggles also gate the band's ANCS handling, writing them wrongly could switch off the notifications that already work. Do not send that packet until we understand it on hardware.

## 9. Settings packets (written to 1514; extracted 9 Nov 2026, all **UNVERIFIED** on our band)

All of these are written to the control characteristic 1514, little-endian. The first byte is the setting's opcode. None of them has been sent by us. Per CLAUDE.md, settings are tested one packet at a time, and **`0x12` is not to be sent** until we understand whether it can switch off ANCS notifications.

| Opcode | Setting | Bytes after the opcode |
|---|---|---|
| `0x06` | Alarms, 3 per packet | three slots of: slot index (1 byte), then 5 alarm bytes (below). 18 bytes, 19 in total |
| `0x08` | Vibration | strength (0 normal, 1 weak, 2 strong), smart vibration (1/0) |
| `0x12` | Calendar and notification toggles (**do not send**) | notifications enabled (1/0), calendar enabled (1/0) |
| `0x14` | Do not disturb | enabled (1/0), start hour, start minute, end hour, end minute |
| `0x15` | Auto power off | enabled (1/0), start hour, start minute, end hour, end minute |
| `0x16` | Day start hour | hour (1 byte) |
| `0x17` | Step goal | goal notification (1/0), goal steps (int32) |
| `0x18` | Status page order | one byte per page id, in order |
| `0x19` | Menu icons | one byte per icon id, in order |
| `0x1A` | Display | font size (0 normal, 1 large), orientation (0 right hand, 1 left hand), language (0 English, 1 Japanese), wake on raise (1/0), design (0 normal, 1 rich), weather in status bar (1/0), display duration in seconds |
| `0x1B` | Home screen icons | left, centre, right icon ids (int16 each) |
| `0x1C` | Button actions | long press action, double click action (int16 each) |
| `0x21` | Camera app type | 1 = Xperia camera app, 0 = other |

**Alarms** (9 slots, sent as three `0x06` packets for slots 0-2, 3-5 and 6-8; every packet always carries 3 slots):
- Each slot: slot index (0-8), then 5 bytes: state (`0x02` on, `0x01` off, `0x00` empty slot), repeat days, smart wake-up margin in minutes (0 = off), hour, minute.
- An empty slot is the slot index followed by five zero bytes.
- **Repeat days** bitmask on the wire: bit 0 Sunday, bit 1 Monday, bit 2 Tuesday, bit 3 Wednesday, bit 4 Thursday, bit 5 Friday, bit 6 Saturday. (Gadgetbridge converts from its own Monday-first mask.) 0 most likely means "once".
- Example (made up): slot 0 on, weekdays, no smart margin, 06:30 = `00 02 3E 00 06 1E`.
- Sending alarms replaces all 9 slots, so the phone must always send the complete set.

Not extracted yet: the id tables for home icons, menu icons, status pages and button actions, the body properties packet details (section 4), and the behaviour, VO2, stress, energy and calories activity parsers.

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
  - **Calendar entries `0x02` confirmed, 9 Nov 2026 (commit `3133cc4`):** the band shows the whole list of upcoming events sent by the app and lets you flick through them. All-day events (sent as 00:00 UTC) not yet checked separately.
  - **Alarms `0x06` on 1514 (commit after `7cb8702`, 9 Nov 2026):** built (9-slot editor, three packets per change), checked in unit tests and the simulator demo. Result on the band: pending. Watch for: the first send replacing any alarms set earlier with Sony's app, the weekday bits (bit 0 = Sunday), and smart wake-up (10 min).
  - **Failed connect attempts at the edge of range:** iOS can report "Failed to encrypt the connection" for a pending reconnect. The app used to give up there, which likely caused the 08:12-13:47 gap. Since commit `6f8edc7` it retries after 2 s: confirmed at 15:52:06, reconnected 39 s later and answered the weather request.

Still open from section 10: subscribing to 4002 and 3002 to see which requests the band sends by itself (this writes the subscription descriptor, so it is the next step up from pure reads).

## 14. Pairing a band without Sony's app (research, 10 Nov 2026)

Nothing here has been tried by us. The owner's band stays bonded and must not be used to test it (CLAUDE.md). Sources are listed at the end of the section.

### 14.1 How Sony's own setup worked on iPhone (Sony help guide, pages 7, 11-13)

- **Pairing happens in iOS Settings, not in the app.** The guide says to connect the band to the phone in the iPhone's Settings > Bluetooth first (device name `WNW-21A`) and only then open the Sony app. The app's own "pairing" step is described as pairing with the app, done after the OS-level connection already exists.
- **Leaving Settings the wrong way breaks it:** once Settings shows "Connected", press Home (swipe up) to leave. Going back to the settings list, or closing the Settings app from the app switcher, disconnects the band.
- After that the Sony app signed in (Sony account or Sign in with Apple), ran a tutorial and wrote "various settings" the user entered. The account sign-in is what died on 28 Feb 2026, which is why Sony and shops say new setup and re-pairing are impossible. That is a limit of Sony's app, not a known limit of the band. Nothing we found says the band itself checks a server or a setup token, and the protocol has no handshake (section 2).
- A passkey: one search summary mentioned a 6-digit passkey shown on the device, but that came from the start guide of the older wena wrist, not wena 3. The wena 3 guide's pairing page is a picture, so whether iOS shows "Pair" or asks for a code is **UNVERIFIED**. Design for both.

### 14.2 Band menu actions (Sony help guide, page 11-12)

On the band: swipe up from the home screen > settings.

| Item (Japanese label) | What Sony says it does |
|---|---|
| Delete pairing (ペアリング削除) | Deletes the band's pairing info. Used to re-pair: delete here, then delete the pairing on the phone, then connect to `WNW-21A` again |
| Initialise (初期化) | Factory reset. Deletes pairing info and all settings and info about paired devices. Keeps Qrio keys and FeliCa (Suica, e-money). Sony says to use it when moving to a new phone. A 2021 owner report adds that it also erases the stored activity history |
| Restart (再起動) | Reboots, settings kept |
| Main power off (主電源OFF, at the bottom of device info) | Full power off; return by holding the button 6 s, "needs a sync with the app" afterwards |
| Forced reset | Hold the power key 10 s while on: forced restart. Sony then says to connect with the app and "rewrite the settings" |

So "Delete pairing" is the gentle route (the band keeps its settings), and "Initialise" is the heavy one. Sony's own text for both ends with "connect to `WNW-21A` again from the phone".

### 14.3 What Gadgetbridge does

- Its device page marks Wena 3 "No-vendor pair": initial pairing works in Gadgetbridge without Sony's app. "Bonding/pairing works" is the author's status line. Nothing more specific (bonding style, passkey, pairing mode) is documented.
- Its general pairing advice: unpair the gadget from the phone's Bluetooth and uninstall the vendor app first, then let Gadgetbridge discover and pair it.
- On every connect it sends the full settings list (section 2), including `0x12`. So a band paired through Gadgetbridge always gets every setting written, which may hide whether a reset band needs any of them.
- Band-side bugs reported by the author (PR #3311, Sept 2023): after unpairing from the phone and deleting the bond in the band's menu, a band reboot made it spam the phone with pairing requests and Gadgetbridge could not find it. Removing a device in Gadgetbridge does not tell the band to unpair. "Pairing is very buggy on the Wena 3 itself."
- The media and camera buttons use the band's HID profile, which the OS connects; on Android it sometimes needs reconnecting in system settings after a long time out of range.

### 14.4 Owner reports after the shutdown

- **Sony and a Sony shop (tecstaff, 12 Feb and 3 Mar 2026):** after 28 Feb, new setup and connection settings are impossible from Sony's app, and deleting the Bluetooth pairing may make re-setup impossible. Standalone functions (steps, heart rate, notifications) keep working on a band that was already set up.
- **Gadgetbridge owner (note.com, 1 Mar 2026, Android):** uninstalled Sony's app but **kept the existing bond**; Gadgetbridge connected by itself and most features work. Sony's customisations were reset to Gadgetbridge's. This does not cover a new phone or a reset band.
- **Moving phones before the shutdown (2021, Android):** charge the band, switch Bluetooth off on the old phone (otherwise the old phone grabbed the band first), initialise the band, then pair from the new phone. Sony's FAQ said initialising was required to connect to a different phone. Other owners added: turn off Bluetooth on every other phone that knew the band, and forget any old `WNW-21A` entry on the new phone first.
- **Our owner (10 Nov 2026, iPhone):** Sony's app is still installed and still opens. Before the shutdown it sometimes asked to re-bond the band if it hadn't been opened for a while; now it just opens and says a re-sync is needed. That fits section 14.1: the Sony app keeps its own app-level link to the band on top of the iOS bond, and that link expires. The iOS bond (notifications, media buttons, our app) is not affected. What the app's re-sync or re-bond would send to the band is unknown, and it can't finish without Sony's login, so it is safest not to tap it.
- **No report found** of anyone pairing a reset or unbonded Wena 3 to an iPhone after the shutdown, or to a new phone with Gadgetbridge after the shutdown. Reddit, X and Kakaku threads could not be searched properly.

### 14.5 What this means for us

- Pairing is plain OS bonding. On iOS the documented route is Settings > Bluetooth > `WNW-21A`. iOS lists it there because the band has an HID profile, and our app then finds it with `retrieveConnectedPeripherals` (section 13). This is the route to build on.
- An app-started pairing (scan, connect, iOS shows its own pairing prompt) only happens if the band answers a read or write with "insufficient authentication". We don't know which characteristics are protected (our bonded band never prompted), so it is a fallback, **UNVERIFIED**.
- The band most likely refuses a second phone while it still holds an old bond (Sony required "Delete pairing" or "Initialise" to change phones). Clearing that is a band-menu action the owner does by hand; the app never sends anything for it.
- Unknown and only testable on a stuck band: whether a reset band shows notifications without the `0x12` toggles packet (its defaults after reset are unknown), whether it asks for weather and calendar by itself, and whether it accepts our verified packets (time, weather, calendar, alarms) straight away.

Sources: Sony wena 3 help guide (https://www.sony.jp/support/smartwatch/helpguide_wena3.pdf), Gadgetbridge Sony page (https://gadgetbridge.org/gadgets/wearables/sony/) and pairing page (https://gadgetbridge.org/basics/pairing/), Gadgetbridge PR #3311 (https://codeberg.org/Freeyourgadget/Gadgetbridge/pulls/3311), tecstaff (https://tecstaff.jp/2026-02-12_wena3.html, https://tecstaff.jp/2026-03-02_wena.html), garmy on note.com (https://note.com/garmy/n/n6e87d564566e), mikan-partners (https://www.mikan-partners.com/archives/4827), wena FAQ (https://wena.jp/supports/faq.html).

## 15. Sony's own app, captured (10 Nov 2026)

Our own capture: the owner tapped **Rewrite settings** in Sony's wena 3 app (still installed, still connecting) on the iPhone 17 Pro, recorded with Apple's iOS Bluetooth logging profile and PacketLogger over USB, exported as BTSnoop and decoded by us. The band was the owner's, firmware `2.40JP`. This is a first-party source under section 0: it shows what Sony's app actually sends, so the byte layouts below no longer depend only on Gadgetbridge. The raw capture stays off the repo (it holds the band's address and serial, the owner's calendar titles and body details).

All writes were ATT Write Requests (with response), one at a time, about 60 ms apart. Values below are the owner's own settings, except body properties, which are left out.

### 15.1 Handles seen (this band, this iPhone; handles are not guaranteed stable, always look up by UUID)

| Handle | What it is | How we know |
|---|---|---|
| `0x1022` | 1503 mode, read returned `02` | read in the capture, 1501 handle order |
| `0x1024` | 1520 info | read returned the firmware name `2.40JP` |
| `0x1026` | 1521 state | read returned battery `0x5E` (94%) |
| `0x1028` | 1514 control | carried `0x10`, `0x11` and all settings opcodes |
| `0x102B` | **new: notification app list** (next characteristic after 1514 in service 1501; UUID not in the capture, to confirm with a read-only discovery) | section 15.3 |
| `0x1052` / `0x1053` | 4002 value / its notify descriptor | calendar entries written here |
| `0x1062` / `0x1063` | 3002 value / its notify descriptor | activity sync as in section 7 |
| `0x1012`, `0x1014` | **unknown service 4201**, characteristics 4202 and 4203 (vendor pattern) | discovered by Sony's app; it only subscribed to 4203 |
| `0x1072`, `0x1074` | **unknown service 4301**, characteristics 4302 (write) and 4303 (notify) | Sony's app wrote short `10 00 06 08 ..` messages and the band answered. Purpose unknown (maybe payment or Riiiver). **Never write** |
| `0x10A2`, `0x10A4` | unknown non-Sony 128-bit service `D44BC439-ABFD-45A2-B575-925416129600` | subscribed only |
| `0x10B4` | unknown notify, band sent `C1 01 00 71 00 ...` | not decoded |

### 15.2 Rewrite settings: what Sony sends on 1514, in order

| # | Bytes (hex) | Meaning, checked against the owner's settings seen in Sony's app |
|---|---|---|
| 1-3 | `06 00 02 7F 00 06 1E 01 00.. 02 00..`, `06 03 ..`, `06 06 ..` | Alarms, layout as section 9. Slot 0 on, every day (`7F`), no smart wake, 06:30; slots 1-8 empty. **Note: this replaced whatever alarms Anew Link had sent.** |
| 4 | `08 00 00` | Vibration: normal (Sony's "Medium"), smart vibration off (Sony's "Stop vibrating at rest" off). Matches |
| 5 | `09 00` | **New opcode, not in Gadgetbridge: disconnection alert.** One byte: `00` off, otherwise the delay in 5-second steps (see 15.5) |
| 6 | `10 xx xx xx xx` | Set time, as section 4 |
| 7 | `11 0B 00` | Time zone +11:00, as section 4 |
| 8 | `12 01 01` | Notifications on, calendar on. **Sony's own app sends this on every rewrite**, see 15.4 |
| 9 | `14 00 00 00 06 00` | Do not disturb off, 00:00-06:00 |
| 10 | `15 00 00 00 06 00` | Auto power off: off, 00:00-06:00. Sony's screen showed 22:00-08:00: the rewrite sent placeholder times, but the settings screen itself sends the real ones (`15 01 16 00 08 00` = on, 22:00-08:00, see 15.5) |
| 11 | `16 00` | Day start 0:00. Matches |
| 12 | `17 01 70 17 00 00` | Goal notification on, 6000 steps (int32). Matches |
| 13 | `18 01 03 07 04 05 02 06` | Status page order, 7 ids (table in 15.5) |
| 14 | `19 07 02 01 03 09 08 04 06 05 00` | Menu (tool screen) order, 10 ids (table in 15.5) |
| 15 | `1A 00 01 00 01 00 00 07` | Display: normal font, left hand, English, raise to wake on, normal design, no weather in status bar, 7 s. **Every field matches** Sony's screen, so the section 9 layout is confirmed |
| 16 | `1B 00 0E 00 0C 00 0A` | Home icons left, centre, right = Stress & Recovery, Heart Rate, Steps. So on the wire each icon is `00` then the id: `0x0E` stress, `0x0C` heart rate, `0x0A` steps |
| 17 | `1C 07 00 06 00` | Long press = weather screen (`07 00`), double press = timer screen (`06 00`). Matches, and these are the **same action codes as the Head Linkage table in section 12** |
| 18 | `1D` + 9 bytes | Body properties. 10 bytes in total; the decoded values are plausible only with **height before weight, both x10**, which confirms the corrected order in section 4. Values withheld |
| 19 | `C0 00 00` | Head Linkage **off** (the owner has no watch head) |
| 20 | `C0 20 01 64 00 00 00 00 00 00 00` | Head indicator = band battery. Byte 3 is `64` (100), where the section 12 report had `00` |
| 21-24 | `C0 10 00 0B 00`, `C0 10 01 01 00`, `C0 11 00 06 01`, `C0 11 01 06 00` | Head buttons: B short notifications screen, B long `01 00` (Alexa screen, matches the reporter's default), A short start or stop timer, A long timer screen |
| 25 | `C0 30 02 01` | Notifications on the watch hands, as section 12 |
| 26 | `04` | **New: a lone `04`**, sent last. Most likely "end of settings" or "apply". **UNVERIFIED** |

Missing from Sony's rewrite: `0x21` camera app type (Xperia only), so iPhone owners never need it.

Status page, menu, home icon and button ids are mapped in 15.5.

### 15.3 Notification app list (new, handle `0x102B`)

This is how the band knows which iPhone apps to show, with what LED colour and vibration, since ANCS itself carries no such settings. Sony's app wrote the whole list twice, then `04`, then `12 01 01` on 1514.

- **Framing:** each write is `[fragment number][byte count][up to 18 bytes]`, so a write is at most 20 bytes. A record longer than 18 bytes continues in fragment `01`. A record of exactly 18 bytes is followed by an empty `01 00`.
- **Record:** kind (`00` app, `01` phone call), name length, name in UTF-8 (the app's display name as iOS shows it, for example `Gmail`, `WhatsApp`, `Proton Mail`; calls use `phone`), then 5 setting bytes, then the list position as int16 (counting down to 0, call is 0).
- **The 5 setting bytes:** LED colour, vibration flags (always `03` here), vibration pattern, vibration count, notifications on (`01`). Same order and same values as the notification packet in section 8. For example `07 03 02 01 01` = white, Basic, once (Gmail as set in Sony's app), `03 03 03 02 01` = green, Rapid, twice (WhatsApp), `07 03 01 00 01` for calls (count `00` = repeat). Colour, pattern and count tables are in 15.5.
- **End of list:** a single `04` on the same characteristic.
- The band seems to match ANCS notifications to this list by app name. Whether an app missing from the list is shown or hidden is **UNVERIFIED** (Sony's screen says only listed apps reach the band).
- **Anew Link (10 Nov 2026):** builds this list in `WenaNotificationList` (unit-tested against the Gmail and call records above) and sends the whole list, then `04`, on every change and in "Send all settings". It finds the characteristic by position: all of 1501 is discovered (read-only), and the first writable characteristic after 1514 that isn't 1503/1514/1520/1521 is used. The band event log (debug builds) records "1501 characteristics: ...", and the Notifications screen shows "Band's list found" with the short id in every build, so the UUID can be written down here once seen. Since 10 Nov 2026 (owner's OK) it sends `12 01 01` on 1514 after the list, as Sony does; never a `00` in either field. Still **UNVERIFIED**: the maximum number of apps (we cap at 20), the maximum name length (we cap at 31 bytes), and whether the list alone would have been enough without `12 01 01`.

### 15.4 What this changes for us

- `0x12` with `01 01` is exactly what Sony's app sends whenever it rewrites settings, and the owner's notifications have kept working. So sending `12 01 01` (both on) matches Sony and is low risk. Sending `00` in either field is still untested and stays forbidden. Lifting the "do not send `0x12`" rule is the owner's call; it would most help a reset band whose defaults are unknown (section 14.5).
- Opcodes `0x08`, `0x16`, `0x17`, `0x1A`, `0x1B` and `0x1C` are now confirmed field by field against Sony's own values. `0x14` and `0x15` are confirmed for the on/off byte only.
- Anew Link can now copy its first settings write from these exact bytes, so nothing visibly changes on the band.
- Sony's "Rewrite settings" also rewrites alarms, Head Linkage and the notification list. Any owner who still uses Sony's app will overwrite Anew Link's alarms that way.
- Sony's app also ran a normal activity sync (section 7 requests, the same layout) and sent calendar entries as in section 5. In Sony's writes the title went in a separate write after the 14-byte header.

### 15.5 One setting at a time (second capture, 10 Nov 2026)

The owner agreed to treat the band as a test device. We changed one setting at a time in Sony's app (driven through iPhone Mirroring) while PacketLogger recorded, then put every setting back. All the writes below went to 1514 unless stated. Each change is sent the moment it is picked, without a separate Save, except the per-app notification screen.

**Button actions** (`0x1C`: long press 2 bytes, then double press 2 bytes). Same codes as Head Linkage (section 12):

| Bytes | Action | Bytes | Action |
|---|---|---|---|
| `00 00` | none | `06 00` | timer screen |
| `01 00` | Alexa mic on | `07 00` | weather screen |
| `02 00` | Qrio Lock screen | `0F 00` | Riiiver |
| `02 01` | Qrio Lock unlock | `10 00` | music screen |
| `02 02` | Qrio Lock lock | `10 01` | music play or pause |
| `03 00` | find your phone screen | `10 02` | music next |
| `04 00` | NFC on/off | `10 03` | music previous |
| `05 00` | do not disturb on/off | | |

Sony's app offers exactly these 15 for both presses.

**Home screen icons** (`0x1B`: three slots, each `00` then the id; Sony re-sends `0x1A` just before every `0x1B`):

| Id | Icon | Id | Icon |
|---|---|---|---|
| `01` | timer | `0D` | VO2 Max |
| `02` | alarm | `0E` | Stress & Recovery |
| `03` | clock | `0F` | Body Energy |
| `04` | Alexa | `10` | Suica balance |
| `06` | Qrio Lock | `11` | Calorie |
| `07` | Edy balance | `12` | Riiiver |
| `08` | presence of unread notifications (seen once, during a reconnect) | `13` | music |
| `09` | schedule | `14` | camera |
| `0A` | Steps | `0B` | Sleep |
| `0C` | Heart Rate | | |

Each slot's list leaves out the icons the other two slots already use.

**Menu (tool screen) ids** (`0x19`, matched by position against Sony's list): `07` weather, `02` alarm, `01` timer, `03` find your phone, `09` camera, `08` music, `04` Alexa, `06` Qrio Lock, `05` payment, `00` settings.

**Status page ids** (`0x18`, matched by position): `01` Steps, `03` Heart Rate, `07` Calorie, `04` VO2 Max, `05` Stress & Recovery, `02` Sleep, `06` Body Energy.

Anew Link sends `0x18` and `0x19` from drag-to-reorder lists, always with every id (leaving an id out to hide an item is untested).

**Vibration** (`0x08`): `08 00 00` medium, `08 01 00` weak, `08 02 00` strong; second byte `01` = "stop vibrating at rest" on. Matches section 9.

**Disconnection alert** (`0x09`, new): `09 00` off, `09 01` on with 5 seconds, `09 18` with 2 minutes. So the byte is the delay in 5-second steps (`0x18` = 24 x 5 = 120 s), and 0 means off.

**Auto power off** (`0x15`): `15 01 16 00 08 00` = on, 22:00 to 08:00; `15 00 16 00 08 00` = off with the same times. **Do not disturb** (`0x14`): `14 01 00 00 06 00` = on, 00:00 to 06:00. Both confirm the section 9 layout.

**Notification master switch:** Sony's Off/On switch sends `12 00 01` (notifications off, calendar on) and `12 01 01` when switched back on. So the first byte after `0x12` is notifications and the second is calendar, as in section 9. Notifications came back after `12 01 01`.

**Per-app notification values** (record bytes in 15.3, and the same values in the section 8 notification packet):
- LED colour: `01` red, `02` yellow, `03` green, `04` cyan, `05` blue, `06` purple, `07` white.
- Vibration pattern: `00` nothing, `02` basic, `03` rapid, `04` triple, `05` step up, `06` step down, `07` warning, `08` siren, `0A` double. Short is `01` or `09` (its test write was missed). Calls use `01`.
- Vibration count: `00` repeat, `01` once, `02` twice, `03` 3 times (4 times presumably `04`).
- **Save** re-sends only the changed app's record on `0x102B` (for example `00 0E 00 05 Gmail 01 03 08 03 01 04 00`), after a lone `01` on 4002.

**"Try this notification pattern on wena"** writes a section 8 notification packet to 4002: `00`, colour, `03`, pattern, count, title length `0x14`, message length `0x13`, flags `01`, kind `00`, action length `00`, a notification id (int32, counting up), a timestamp, then the texts "(Notification title)" and "(Notification text)". This confirms the section 8 layout on our band.

**ANCS seen on the wire:** the same capture shows iOS sending ANCS Notification Source and Data Source packets to the band (the band asks for the app identifier, title and message). So the band matches notifications to its app list using ANCS data. Their content is private and not recorded.

**Activity settings** (birth date, gender, height, weight, resting heart rate, step goal) were viewed but not changed. The resting heart rate does not appear in any packet seen so far.

**Opening Sony's app** sends the full notification list, `12 01 01`, `04`, time, time zone, the calendar and a short activity sync, every time.
