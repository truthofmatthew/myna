# Chrome Web Store listing

Everything to paste into the Chrome Web Store developer dashboard for the Myna extension. The images in this folder are rendered from `src/` by `make.sh`.

## Package

Upload `Myna-chrome-extension.zip` from the latest release. It is the `chrome` folder with `manifest.json` at its root.

## Store listing tab

**Name** (from the manifest)

Myna

**Summary** (from the manifest's description, 132 characters max)

Use your Android phone's camera and mic in Google Meet.

**Description**

```
Turn your Android phone into a webcam and microphone for Google Meet.

Myna adds your phone's cameras and mic to Meet's device lists, next to your built-in ones. Pick "Myna Front Camera (phone)" or "Myna Back Camera (phone)" under Video, and "Myna Mic (phone)" under Audio. Prop the phone up wherever the light is good; turn it sideways and the picture turns with it.

What you get
• Front or back camera, 1280 × 720 at 30 frames a second
• The phone's mic as its own device
• Mix and match: phone camera with your computer's mic, or the other way round
• No cables and no driver: the video is decoded right in the tab

What you need
This extension works together with the free Myna apps:
• Myna for macOS (macOS 14 or later), which receives the stream from your phone
• Myna for Android (Android 12 or later), which sends the camera and mic over your Wi-Fi
Download both, and follow the three-step setup, at https://truthofmatthew.com/projects/myna/

How it works
The phone sends its camera and mic to the Myna app on your Mac over your Wi-Fi, encrypted. The Mac app serves them only to your own computer, at 127.0.0.1. This extension reads them from there and hands them to Meet. Nothing goes to any server, and there's no account.

Free and open source (MIT). Read the code, report a problem or help out: https://github.com/truthofmatthew/myna

The Myna apps also bring your phone's texts and calls to the Mac. This extension only handles the camera and mic.
```

**Category:** Communication

**Language:** English

**Graphic assets**

| Field | File |
| --- | --- |
| Store icon (128 × 128) | `chrome/icons/icon-128.png` |
| Screenshots (1280 × 800), in this order | `screenshot-1-meet.png`, `screenshot-2-how.png`, `screenshot-3-setup.png`, `screenshot-4-camera.png`, `screenshot-5-private.png` |
| Small promo tile (440 × 280) | `promo-small-440x280.png` |
| Marquee promo tile (1400 × 560) | `promo-marquee-1400x560.png` |

**Official URL:** none (needs a Search Console-verified site; skip)

**Homepage URL:** https://truthofmatthew.com/projects/myna/

**Support URL:** https://github.com/truthofmatthew/myna/issues

## Privacy tab

**Single purpose**

```
Adds the user's Android phone's camera and microphone, streamed by the Myna app running on the same computer, to Google Meet's camera and microphone choices.
```

**Permission justifications**

Host permission `http://127.0.0.1:8737/*`:

```
The Myna desktop app serves the phone's camera and microphone streams on this local address. The extension fetches the streams from there and nowhere else. It never reaches the internet.
```

Content scripts on `https://meet.google.com/*`:

```
Meet decides which cameras and microphones to offer. The content script adds the phone's camera and mic to that list and supplies their video and audio when the user picks them. It does not read or change anything else on the page.
```

Web-accessible resource `relay.html`:

```
A hidden frame inside Meet that fetches the local stream with the extension's own permission and passes the bytes to the content script.
```

**Remote code:** No, I am not using remote code. All JavaScript ships in the package.

**Data usage:** tick nothing. The extension collects no user data. Video and audio go from the local Myna app into the Meet tab the user is in, and never to the developer or a third party.

Tick all three certifications:
- I do not sell or transfer user data to third parties, outside of the approved use cases.
- I do not use or transfer user data for purposes that are unrelated to my item's single purpose.
- I do not use or transfer user data to determine creditworthiness or for lending purposes.

**Privacy policy URL:** https://truthofmatthew.com/projects/myna/privacy/

## Distribution tab

**Visibility:** Public. **Regions:** all. **Pricing:** free.

## Notes for the reviewer

The dashboard has a field for test instructions. Paste:

```
The extension needs the Myna desktop app and an Android phone running Myna to show a picture. Without them, the three Myna devices still appear in Meet's camera and microphone lists (open Meet › Settings › Video and Audio), and choosing one gives a blank picture while the page's console logs "[myna] phone stream stopped: Myna isn't running on this Mac".

Full setup: https://github.com/truthofmatthew/myna#install
Source: https://github.com/truthofmatthew/myna/tree/main/chrome
```
