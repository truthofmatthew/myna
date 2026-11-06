# Myna

Texts, calls and your phone's camera on your Mac, for Android. Read and send SMS and RCS messages, make and answer calls, and use the phone as the camera and mic in Google Meet.

Work in progress. The plan is in [docs/PLAN.md](docs/PLAN.md), test results in [docs/SPIKES.md](docs/SPIKES.md), and the wire format in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## What works so far

- **Phone camera and mic in Google Meet**, over Wi-Fi, through the Chrome extension. Front or back camera; the picture turns upright as you rotate the phone.
- Texts and calls aren't built yet.

## Try it

1. Mac: `mac/install.sh` builds Myna and puts it in /Applications. It runs in the menu bar.
2. Android: build `android/` with `./gradlew assembleDebug` and install the APK (`adb install app/build/outputs/apk/debug/app-debug.apk`).
3. Pair: Myna menu › Pair Phone…, then scan the code with the phone's camera. The phone and Mac must be on the same Wi-Fi.
4. Chrome or Edge: load `chrome/` as an unpacked extension. In the site settings for meet.google.com, allow **Local network access**.
5. In Meet, pick **Myna Front Camera (phone)** and **Myna Mic (phone)**.

- `mac/`: the Mac app (Swift)
- `android/`: the Android app (Kotlin)

MIT License.
