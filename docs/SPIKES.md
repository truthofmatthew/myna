# Phase 0 spikes

Test phone: Galaxy S24 FE (SM-S721B, Exynos 2400e), Android 17 (API 37), One UI 9.0. Mac: macOS 27.0, Xcode 27.1.

## Camera and mic stream: works

`scrcpy 5.0.1 --video-source=camera --camera-id=1 --camera-size=1280x720 --camera-fps=30 --audio-source=mic` over USB recorded 310 frames in about 10.4 s (30 fps), H.264 720p plus Opus 48 kHz.

- Cameras: 0 back 4080x3060, 1 front 3648x2736, 2 back 4000x3000, 3 front 3280x2268. All at 15/20/24/30 fps.
- Hardware encoders: `c2.exynos.h264.encoder` and `c2.exynos.hevc.encoder`. Opus and AAC are software only.
- Not measured yet: latency from camera to screen. That needs someone watching a clock on both screens.

## SMS and RCS: plan changes

- The default SMS app is **Samsung Messages** (`com.samsung.android.messaging`), not Google Messages, and the dialer is Samsung's.
- Recent incoming messages are in the SMS provider (`content://sms`), with dates matching their notifications. So for this phone the SMS provider covers incoming texts and the notification listener is a backup, not the main path.
- Not tested yet: replying from a live Samsung Messages notification. There was no unread message notification to inspect.

## Bluetooth hands-free calling: control works, audio not yet

- The macOS 27 SDK still ships `IOBluetoothHandsFreeDevice` (dial, answer, end, move audio to the Mac or phone, caller ID, call list). None of it is marked deprecated.
- `spikes/hfp` is a command-line test tool. A bare binary is killed by macOS privacy checks, which look at the launching process, so it has to run as a small `.app` with `NSBluetoothAlwaysUsageDescription`, started with `open`. stdout must be line-buffered or the log stays empty until exit.
- **Connects:** the service-level connection comes up in about 2 s. The phone reports service, signal, battery and call setup, and offers SMS notifications over Bluetooth (`+CNMI`).
- **Status works:** calls dialed on the phone show up on the Mac as `callSetup=2` (dialing), then 0 when they end.
- **Dialing works:** `dialNumber` from the Mac made the phone place the call (17:15:24).
- **Audio failed:** the phone routed the call to Bluetooth audio aimed at the Mac (`TYPE_BLUETOOTH_SCO`, Mac address `…:40:F2`), then fell back to the earpiece 0.6 s later (`SamsungBluetoothStateReceiver`). The Mac never reported the audio link opening. The call itself ended with the carrier error `404 UNOBTAINABLE_NUMBER`, so it never connected.
- Next: dial a number that answers, then check whether the audio link opens on its own or after `transferAudioToComputer`, and whether macOS shows the phone as a mic and speaker.

## Camera extension in Meet: not started

- This Mac only has an `Apple Development` certificate. Activating a system extension needs a paid team with the System Extension capability; shipping it needs a Developer ID and notarization.
