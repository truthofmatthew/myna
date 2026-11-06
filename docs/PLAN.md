# Myna plan

Myna links an Android phone to a Mac: texts, calls, and the phone's camera and mic as a webcam for Google Meet. Target devices: Galaxy S24 on One UI 9 (Android 17) and macOS 27.

## Layout

- `mac/`: Swift, XcodeGen `project.yml` (same setup as Bower), no dependencies. Menu-bar app, camera extension, audio plug-in.
- `android/`: Kotlin, Gradle, AndroidX only. Distributed through GitHub Releases and F-Droid; Google Play won't accept a non-default SMS app.
- `docs/`: this plan and `PROTOCOL.md`, the wire format both sides follow.

## Platform facts that shape the design (checked November 2026)

- macOS 27 has no API for third-party phones in iPhone Mirroring. We use a Core Media I/O camera extension (virtual camera), an Audio Server plug-in (virtual mic), IOBluetooth hands-free (calls) and Bonjour with Network.framework (local network).
- Android 17, for apps targeting API 37:
  - Talking to the Mac over Wi-Fi needs the new `ACCESS_LOCAL_NETWORK` runtime permission.
  - Texts containing one-time codes are hidden from SMS-reading apps for 3 hours. Default SMS apps and companion-device apps are exempt; reading notifications avoids the delay.
  - Background audio needs a foreground service started while the app is visible.
- The companion-device "computer" profile is limited to privileged apps such as Phone Link.
- The S24 doesn't get Samsung's USB webcam mode (S26 only), and Camera Share is Windows-only.
- The S24 uses Google Messages, so most chats are RCS, which Android's SMS APIs can't see.
- Sideloaded apps must be allowed "restricted settings" once before they can use SMS or the notification listener.

## Features

**SMS**
- Incoming SMS and RCS come through a `NotificationListenerService`, with no 3-hour delay.
- History comes from the SMS provider (SMS and MMS only).
- Replies go through the notification's reply action, so RCS replies work. New threads are sent with `SmsManager`.
- On the Mac: a conversations window and notifications with a Reply field.

**Calls** (control-only; see SPIKES.md)
- The Mac connects as a Bluetooth hands-free device (`IOBluetoothHandsFreeDevice`) to dial, answer, reject, hang up and get caller ID and call state.
- macOS 27 refuses hands-free call audio (`kIOReturnUnsupported`), and Android can't relay cellular call audio over Wi-Fi. The conversation stays on the phone.
- The Android app adds contact names and call history over Wi-Fi.

**Camera and mic**
- Android: a foreground service (camera and microphone types) captures with CameraX, encodes H.264 with MediaCodec, and sends 48 kHz mono PCM audio.
- Mac: VideoToolbox decodes into the camera extension.
- The mic plays into BlackHole first; our own audio plug-in ships before 1.0.

**Transport**
- Bonjour service `_myna._tcp`. Pairing works by scanning a QR code on the Mac, which carries a self-signed certificate the phone then pins.
- One TLS control connection with length-prefixed JSON and one media connection. USB through `adb reverse` comes later.

## Phases

0. Spikes:
   - hands-free calling between macOS 27 and the S24;
   - the camera extension appearing in Meet in Chrome;
   - RCS reply from a notification on One UI 9;
   - camera latency measured with `scrcpy --video-source=camera --audio-source=mic`.
1. Pairing, transport, the Mac menu-bar app and the Android foreground service.
2. SMS.
3. Camera and mic.
4. Calls (hands-free or control-only, depending on spike 0).
5. Installer, notarization, README, release.

## Signing

- The camera extension needs a Developer ID, the system-extension entitlement, notarization, and the app installed in `/Applications`.
- The audio plug-in installs to `/Library/Audio/Plug-Ins/HAL` with an admin password.
