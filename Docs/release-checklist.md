# Release checklist (TestFlight and App Store)

What's left before other Wena 3 owners can install Anew Link. Most of it needs the owner's Apple account, so it can't be done from the code.

## Your next steps, in order (9 Nov 2026)

Done in the code already: paid team `WVWWUXQ867` selected, final bundle ID `com.donut32.anew-link` (registered to the paid team, signed Release build checked), the encryption declaration, a clean history check (no serial, address or private emails), and a Release build for real iPhones.

1. **Wait for the membership email** ("Welcome to the Apple Developer Program"). Then in Xcode: **Xcode > Settings > Accounts**, select your Apple ID, and click **Download Manual Profiles** (or remove and re-add the account) until a team **without** "(Personal Team)" appears.
2. **Pick the paid team:** click the blue WenaCompanion project > target **MyApp** > **Signing & Capabilities** > **Team**: choose the new team. Check HealthKit and Background Modes still show without errors. (This changes `DEVELOPMENT_TEAM` in the project file; commit it.)
3. **Delete the old app from your iPhone** (the bundle ID changed, so the old copy won't update), then Cmd+R. Grant the permissions again. Your Health data stays.
4. ✅ Done 9 Nov 2026. **Make the repo public:** github.com/donut3226/anew-link > **Settings** > **General** > scroll to **Danger Zone** > **Change visibility** > **Public**.
5. ✅ Done 9 Nov 2026 (live). **Publish the privacy policy:** same Settings > **Pages** > Source **Deploy from a branch** > Branch **main**, folder **/ (root)** > **Save**. After a minute or two it's at **https://donut3226.github.io/anew-link/Docs/privacy-policy.html**. Open it to check.
6. ✅ Done 9 Nov 2026. **Create the app in App Store Connect:** appstoreconnect.apple.com > **Apps** > **+** > **New App**: platform iOS, name **Anew Link**, primary language English, bundle ID **com.donut32.anew-link**, SKU `anewlink`, access Full.
7. ✅ First build 1.0 (1) uploaded 9 Nov 2026 from the command line. Later builds: run `Scripts/upload-testflight.sh`. **Upload a build (by hand, if ever needed):** in Xcode choose **Any iOS Device (arm64)** as the destination, then **Product > Archive**. When the Organizer opens: **Distribute App** > **TestFlight & App Store** (or **TestFlight Internal Only**) > follow the defaults.
8. ✅ Done 9 Nov 2026: internal group "Me" with the Hotmail Apple ID, build 1.0 (1) installed from TestFlight on the owner's iPhone. **TestFlight, just you:** in App Store Connect > your app > **TestFlight**, wait for the build to finish processing (often 10-30 minutes), add yourself under **Internal Testing**, and install the **TestFlight** app on your iPhone. No Apple review is needed for internal testers.
9. ✅ Submitted 10 Nov 2026: external group "Wena owners", build 1.0 (67) waiting for Beta App Review; test information saved (feedback email anewlink@outlook.com.au). When approved: enable the **Public Link** in the group and post the invite (section 5). **Originally:** add an **External Testing** group (needs a short beta review: paste the review notes from section 3), or submit to the App Store with the listing in section 2.

## 1. Apple Developer Program (owner)

- TestFlight and the App Store need the paid **Apple Developer Program** (99 USD / 149 AUD a year; the owner joined on 9 Nov 2026). The free Personal Team used so far only installs on your own devices, and its builds expire after 7 days.
- After joining, set the team in Xcode (target MyApp > Signing & Capabilities). The bundle ID is `com.donut32.anew-link` (it can never change after the first upload). `com.donut32.openband` and `com.donut32.anewlink` were claimed by the free Personal Team while Xcode was open, so they can't be used by the paid team.
- Check the capabilities carry over: HealthKit, Background Modes (uses Bluetooth LE accessories).

## 2. App Store Connect listing (owner)

- **Name:** "Anew Link". **Subtitle** idea: "Unofficial companion for Wena 3". Keep "unofficial" visible; don't use Sony logos or product photos.
- **Privacy policy URL:** publish `Docs/privacy-policy.md` (for example with GitHub Pages, which needs the repository to be public, or any simple web page) and paste the link. Apple requires it because the app uses Health.
- **App Privacy ("nutrition label"):** the app collects no data in Apple's sense. The rounded location goes to Open-Meteo only to answer the forecast request and isn't stored by us. Answer "Data Not Collected", and re-check against Apple's current definitions when filling it in.
- **Category:** Health & Fitness or Utilities. **Price:** free.
- **Screenshots:** take them in the simulator using **Try the demo** (no band needed).
- **Export compliance:** the app only uses Apple's standard HTTPS, so it's exempt. `ITSAppUsesNonExemptEncryption = NO` is already in `Config/Info.plist`, so App Store Connect won't ask for each build.

## 3. Notes for App Review (paste into "App Review Information")

> Anew Link is an unofficial, free, open-source companion for the Sony Wena 3 smart watch band, whose official app Sony discontinued on 28 February 2026. Reviewers won't have a band, so the app includes a demo mode: open the app, wait a few seconds until it says the band wasn't found, then tap "Try the demo" under Status. The demo shows every feature with made-up data and sends or saves nothing. Bluetooth background mode is used to keep the connection to the band so it can answer the band's own requests (time, weather, calendar, song title, find my phone) while the phone is locked.

## 4. Before the first public build (code)

- Debug-only sections ("Debug only", "Band requests (debug)") are already left out of Release builds by `#if DEBUG`. Do one Release run on the phone to confirm.
- Finish the hardware tests in the plan's test backlog (automatic activity save, heart rate, calendar, find my phone vibration).
- Re-check the spec against current Gadgetbridge (spec section 11) for any protocol changes.
- Make the GitHub repository public if the privacy policy is hosted there, and check nothing private is in its history (the band's serial must never be in commits).

## 5. External TestFlight (other Wena owners), drafted 10 Nov 2026

External testers need one short Beta App Review per version (usually under a day). After that, new builds of the same version usually go out without another review. A **public link** lets anyone join (up to 10,000 people), so no email addresses need collecting.

**Steps in App Store Connect** (Anew Link > TestFlight):
1. **Test Information** (left sidebar): paste the Beta App Description and Feedback Email below, the privacy policy URL (https://donut3226.github.io/anew-link/Docs/privacy-policy.html), and the review notes from section 3 (also add the line below about settings).
2. **External Testing > +**: create a group, for example "Wena owners".
3. Add the newest build to the group, answer "What to Test", and **Submit for Review**.
4. Once approved: in the group, **Public Link > Enable**, optionally with a tester limit, and share the link.

**Beta App Description** (testers see this):
> Anew Link is a free, open-source and unofficial companion app for the Sony Wena 3 band (WNW-21A), made by an owner after Sony ended support on 28 February 2026. It keeps the band's time and weather up to date, shows your calendar and the song playing, sets alarms and band settings, rings your phone from the band, and saves steps and heart rate to Apple Health. Not affiliated with or endorsed by Sony. Suica, payments, Alexa and Qrio can't be brought back.

**What to Test** (per build):
> Pair your band in iOS Settings > Bluetooth if it isn't already, open the app, and check: time and weather on the band, an alarm a few minutes ahead, Band settings (try "Feel it on the band"), and Activity > Save to Apple Health. If your band lost its pairing after Sony's app stopped working, please say so in feedback: that's the next thing being built. Use the screenshot or "Send Beta Feedback" in TestFlight to report anything odd.

**Extra review note** (add to section 3's notes):
> The Band settings screen and its "Feel it on the band" button only send settings the user changes, to the user's own band. In demo mode nothing is sent.

**Feedback email:** the owner's choice (TestFlight shows it to testers; a separate address from the Apple IDs is a good idea).

**Where Wena owners are** (the owner posts; nothing is posted automatically):
- The Gadgetbridge Wena 3 issues and discussions on Codeberg.
- Japanese owner blogs and X, since most Wena 3 bands were sold in Japan (tecstaff, note.com writers in spec 14.4). The app is English-only for now, so say so.
- Reddit or watch forums where Wena bands were discussed.

**Invite post (English):**
> Wena 3 owners on iPhone: Sony's app support ended in February, so I built a free, open-source replacement called Anew Link (unofficial). It brings back weather and calendar on the band, alarms, band settings, find my phone, song titles, and saves steps and heart rate to Apple Health. It's in TestFlight beta: [public link]. Code: https://github.com/donut3226/anew-link. I'd especially like to hear from anyone whose band lost its pairing.

**Invite post (Japanese draft, English-only app):**
> wena 3 を iPhone で使っている方へ。Sony のアプリのサポートが2月で終了したため、無料・オープンソースの非公式アプリ「Anew Link」を作りました。バンドへの天気・カレンダー表示、アラーム、バンドの設定、スマホを探す、曲名表示、歩数と心拍数の Apple ヘルスケアへの保存ができます。TestFlight でベータ版を公開中です: [public link]。アプリは現在英語のみです。ペアリングが外れてしまったバンドをお持ちの方の感想を特に歓迎します。
