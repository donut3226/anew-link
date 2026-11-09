# Release checklist (TestFlight and App Store)

What's left before other Wena 3 owners can install Anew Link. Most of it needs the owner's Apple account, so it can't be done from the code.

## 1. Apple Developer Program (owner)

- TestFlight and the App Store need the paid **Apple Developer Program** (99 USD a year, or a fee waiver for some non-profits). The free Personal Team used so far only installs on your own devices, and its builds expire after 7 days.
- After joining, set the team in Xcode (target MyApp > Signing & Capabilities) and keep the bundle ID `com.donut32.openband`, or choose a final one before the first upload (it can't change after release).
- Check the capabilities carry over: HealthKit, Background Modes (uses Bluetooth LE accessories).

## 2. App Store Connect listing (owner)

- **Name:** "Anew Link". **Subtitle** idea: "Unofficial companion for Wena 3". Keep "unofficial" visible; don't use Sony logos or product photos.
- **Privacy policy URL:** publish `Docs/privacy-policy.md` (for example with GitHub Pages, which needs the repository to be public, or any simple web page) and paste the link. Apple requires it because the app uses Health.
- **App Privacy ("nutrition label"):** the app collects no data in Apple's sense. The rounded location goes to Open-Meteo only to answer the forecast request and isn't stored by us. Answer "Data Not Collected", and re-check against Apple's current definitions when filling it in.
- **Category:** Health & Fitness or Utilities. **Price:** free.
- **Screenshots:** take them in the simulator using **Try the demo** (no band needed).
- **Export compliance:** the app only uses Apple's standard HTTPS, so it's exempt. Answer "No" to non-exempt encryption, or add `ITSAppUsesNonExemptEncryption = NO` to `Config/Info.plist`.

## 3. Notes for App Review (paste into "App Review Information")

> Anew Link is an unofficial, free, open-source companion for the Sony Wena 3 smart watch band, whose official app Sony discontinued on 28 February 2026. Reviewers won't have a band, so the app includes a demo mode: open the app, wait a few seconds until it says the band wasn't found, then tap "Try the demo" under Status. The demo shows every feature with made-up data and sends or saves nothing. Bluetooth background mode is used to keep the connection to the band so it can answer the band's own requests (time, weather, calendar, song title, find my phone) while the phone is locked.

## 4. Before the first public build (code)

- Debug-only sections ("Debug only", "Band requests (debug)") are already left out of Release builds by `#if DEBUG`. Do one Release run on the phone to confirm.
- Finish the hardware tests in the plan's test backlog (automatic activity save, heart rate, calendar, find my phone vibration).
- Re-check the spec against current Gadgetbridge (spec section 11) for any protocol changes.
- Make the GitHub repository public if the privacy policy is hosted there, and check nothing private is in its history (the band's serial must never be in commits).
