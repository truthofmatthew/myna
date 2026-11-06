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

## Bluetooth hands-free calling: call control works, audio is not supported

- The macOS 27 SDK still ships `IOBluetoothHandsFreeDevice`, and none of it is marked deprecated.
- `spikes/hfp` is the test tool. A bare binary is killed by macOS privacy checks, which look at the launching process, so it runs as a small `.app` with `NSBluetoothAlwaysUsageDescription`, started with `open`. stdout must be line-buffered or the log stays empty until exit.
- **Connects:** the service-level connection comes up in about 2 s. The phone reports service, signal, battery and call setup, and offers SMS notifications over Bluetooth (`+CNMI`).
- **Status works:** calls dialed on the phone show up on the Mac as `callSetup=2` (dialing), 3 (ringing), `callActive=1` (connected), then 0.
- **Dialing and hanging up work:** `dialNumber("162")` placed the call (17:16:47); it connected at 17:16:51, and `endCall` hung it up at 17:17:13.
- **Audio fails:** the phone tries Bluetooth audio to the Mac, then falls back to the earpiece within 0.6 s. Asking for it with `transferAudioToComputer` returned `kIOReturnUnsupported` (0xE00002C7) for the audio link, and no Bluetooth audio device appeared in macOS. macOS 27 doesn't let a third-party app carry call audio as a hands-free device.
- **Decision:** calls are control-only. The Mac shows the caller and can dial, answer, reject and hang up; the conversation happens on the phone (or on earbuds connected to the phone). Android can't relay cellular call audio over Wi-Fi either, so there's no other route.

## Camera extension in Meet: not started

- This Mac only has an `Apple Development` certificate. Activating a system extension needs a paid team with the System Extension capability; shipping it needs a Developer ID and notarization.
