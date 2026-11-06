# Myna

Texts, calls and your phone's camera on your Mac, for Android. Read and send SMS and RCS messages, make and answer calls, and use the phone as the camera and mic in Google Meet.

Work in progress. The plan is in [docs/PLAN.md](docs/PLAN.md), test results in [docs/SPIKES.md](docs/SPIKES.md), and the wire format in [docs/PROTOCOL.md](docs/PROTOCOL.md).

## What works so far

- **Phone camera and mic in Google Meet**, over Wi-Fi, through the Chrome extension. Front or back camera; the picture turns upright as you rotate the phone.
- **Texts on the Mac**: conversations from the phone, sending, and notifications with a Reply field.
- **Calls from the Mac**: incoming-call notifications with Answer and Decline, Hang Up in the menu, and a Call button in Messages. The phone switches to speaker so you never touch it (needs `adb shell appops set com.truthofmatthew.myna MANAGE_ONGOING_CALLS allow` once); macOS doesn't let apps carry call audio, so the phone's mic and speaker are used.

## Try it

1. Mac: `mac/install.sh` builds Myna and puts it in /Applications. It runs in the menu bar.
2. Android: build `android/` with `./gradlew assembleDebug` and install the APK (`adb install app/build/outputs/apk/debug/app-debug.apk`).
3. Pair: Myna menu › Pair Phone…, then scan the code with the phone's camera. The phone and Mac must be on the same Wi-Fi. After that, opening Myna on the phone connects it.
4. Chrome or Edge: load `chrome/` as an unpacked extension.
5. In Meet, pick **Myna Front Camera (phone)** and **Myna Mic (phone)**.

- `mac/`: the Mac app (Swift)
- `android/`: the Android app (Kotlin)

MIT License.
