# Release checklist (TestFlight and App Store)

What's left before other Wena 3 owners can install Anew Link. Most of it needs the owner's Apple account, so it can't be done from the code.

## Your next steps, in order (9 Nov 2026)

Done in the code already: final bundle ID `com.donut32.anewlink`, the encryption declaration, a clean history check (no serial, address or private emails), and a Release build for real iPhones.

1. **Wait for the membership email** ("Welcome to the Apple Developer Program"). Then in Xcode: **Xcode > Settings > Accounts**, select your Apple ID, and click **Download Manual Profiles** (or remove and re-add the account) until a team **without** "(Personal Team)" appears.
2. **Pick the paid team:** click the blue WenaCompanion project > target **MyApp** > **Signing & Capabilities** > **Team**: choose the new team. Check HealthKit and Background Modes still show without errors. (This changes `DEVELOPMENT_TEAM` in the project file; commit it.)
3. **Delete the old app from your iPhone** (the bundle ID changed, so the old copy won't update), then Cmd+R. Grant the permissions again. Your Health data stays.
4. ✅ Done 9 Nov 2026. **Make the repo public:** github.com/donut3226/anew-link > **Settings** > **General** > scroll to **Danger Zone** > **Change visibility** > **Public**.
5. ✅ Done 9 Nov 2026 (live). **Publish the privacy policy:** same Settings > **Pages** > Source **Deploy from a branch** > Branch **main**, folder **/ (root)** > **Save**. After a minute or two it's at **https://donut3226.github.io/anew-link/Docs/privacy-policy.html**. Open it to check.
6. **Create the app in App Store Connect:** appstoreconnect.apple.com > **Apps** > **+** > **New App**: platform iOS, name **Anew Link**, primary language English, bundle ID **com.donut32.anewlink** (if it isn't in the list, register it first at developer.apple.com > Identifiers), SKU `anewlink`, access Full.
7. **Upload a build:** in Xcode choose **Any iOS Device (arm64)** as the destination, then **Product > Archive**. When the Organizer opens: **Distribute App** > **TestFlight & App Store** (or **TestFlight Internal Only**) > follow the defaults.
8. **TestFlight, just you:** in App Store Connect > your app > **TestFlight**, wait for the build to finish processing (often 10-30 minutes), add yourself under **Internal Testing**, and install the **TestFlight** app on your iPhone. No Apple review is needed for internal testers.
9. **Later, for other Wena owners:** add an **External Testing** group (needs a short beta review: paste the review notes from section 3), or submit to the App Store with the listing in section 2.

## 1. Apple Developer Program (owner)

- TestFlight and the App Store need the paid **Apple Developer Program** (99 USD / 149 AUD a year; the owner joined on 9 Nov 2026). The free Personal Team used so far only installs on your own devices, and its builds expire after 7 days.
- After joining, set the team in Xcode (target MyApp > Signing & Capabilities). The bundle ID is `com.donut32.anewlink` (changed from `com.donut32.openband` on 9 Nov 2026, before the first upload; it can never change after that).
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
