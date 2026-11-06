# Myna protocol, version 1

The Mac app listens; the phone connects to it. Everything after the 16-byte handshake is encrypted.

## Pairing

The Mac shows a QR code with this link:

```
myna://pair?id=<mac id>&n=<mac name>&h=<ip>&p=<port>&k=<key>
```

- `id`: the Mac's random id (UUID string).
- `n`: the Mac's name, URL-encoded, shown on the phone.
- `h`, `p`: the Mac's current IP address and port, a fallback when Bonjour doesn't find it.
- `k`: a random 32-byte pairing key, base64url without padding. The Mac keeps it in the Keychain; the phone keeps it in its private app storage.

The phone's camera app opens the link, and the Myna app saves the pairing. Showing a new QR code (Pair again) makes a new key, so old phones stop working.

## Finding the Mac

The Mac advertises Bonjour service `_myna._tcp` with TXT record `id=<mac id>`. The phone looks for that service with `NsdManager`, picks the one with its saved id, and falls back to the saved `h:p`.

## Handshake

1. Phone → Mac: `MYNA` (4 bytes), version `1` (1 byte), 16 random bytes `pn`, then 11 zero bytes. 32 bytes in total.
2. Mac → phone: 16 random bytes `mn`.
3. Both derive two 32-byte keys with HKDF-SHA256, using the pairing key as input key material and `pn || mn` as salt:
   - phone → Mac: info `myna1 phone to mac`
   - Mac → phone: info `myna1 mac to phone`
4. The phone's first frame must be a `hello` message. If the Mac can't decrypt it, the phone isn't paired, and the Mac closes the connection.

## Frames

```
[length u32 big-endian][AES-256-GCM ciphertext + 16-byte tag]
```

- The nonce is 12 bytes: 4 zero bytes, then a u64 big-endian counter. The counter starts at 0 for each direction and goes up by one per frame. No associated data.
- A frame that fails to decrypt closes the connection.
- The largest allowed length is 4 MiB.

Plaintext starts with a type byte:

| Type | Name | Body |
|---|---|---|
| 1 | message | UTF-8 JSON |
| 2 | video | `[flags u8][pts µs u64][H.264 Annex B]`: flags bit 0 = key frame, bit 1 = config (SPS/PPS) |
| 3 | audio | `[flags u8][pts µs u64][one Opus packet, 48 kHz mono, 20 ms]` |

## Messages

Phone → Mac:

- `{"t":"hello","name":"Galaxy S24 FE","app":1}`: first frame on every connection.
- `{"t":"video","w":1280,"h":720,"rotation":180}`: sent when the camera starts and when the phone turns. `rotation` is the clockwise turn, in degrees, that makes the picture upright. The phone sends frames as the sensor gives them; the viewer turns them.

Mac → phone:

- `{"t":"camera","on":true,"camera":"front"}`: start (or switch) the camera; `"camera":"back"` for the back camera. `{"t":"camera","on":false}` stops it.
- `{"t":"keyframe"}`: send a key frame now (a new viewer joined).
- `{"t":"mic","on":true}` / `{"t":"mic","on":false}`.
- `{"t":"ping"}`: every 10 s. The phone answers `{"t":"pong"}`. Either side drops the connection after 30 s of silence.

## Text messages

A message object: `{"id":55743,"thread":12,"address":"+989121234567","name":"Sara","body":"…","date":1793968465081,"type":1,"read":true}`.
`type` is Android's: 1 received, 2 sent, 4 sending, 5 failed, 6 queued. `date` is milliseconds since 1970. `name` is the contact name, or missing.

Mac → phone:

- `{"t":"sms.sync"}`: send the newest 2000 messages. The Mac sends this after every `hello`.
- `{"t":"sms.send","to":"+989121234567","body":"…","ref":"<uuid>"}`: send a text from the phone's default SMS SIM.
- `{"t":"sms.read","address":"…","name":"…","ids":[…]}`: mark a conversation read by pressing "Mark as read" on Samsung Messages' notification for it (needs Notification access on the phone).
- `{"t":"sms.batch","id":"<uuid>","delete":[ids],"read":[ids],"block":["…"],"unblock":["…"]}`: changes only the SMS app may make. The phone saves the batch and shows a notification; when you tap it, Myna takes the SMS role, applies the batch, and opens Samsung Messages so it can take the role back. An empty batch just reads the phone's block list.

Phone → Mac:

- `{"t":"sms.list","messages":[…]}`: answer to `sms.sync`, newest first.
- `{"t":"sms.new","messages":[…]}`: messages that appeared since the last list, received or sent (including ones typed on the phone).
- `{"t":"sms.sent","ref":"<uuid>","ok":true}`: the carrier accepted (or refused) a text the Mac asked to send.
- `{"t":"sms.read.done","ids":[…],"ok":false}`: no notification to press; the Mac adds the ids to its next batch.
- `{"t":"sms.batch.done","id":"<uuid>","deleted":[ids],"blocked":["…"]}`: the batch ran; `blocked` is the phone's whole block list afterwards.
- `{"t":"sms.error","error":"…"}`: texts aren't available, for example because SMS permission wasn't granted.

## Calls

Control only: the conversation stays on the phone (or earbuds connected to it). macOS 27 won't let an app carry call audio, and Android won't let one relay it.

Phone → Mac:

- `{"t":"call.state","state":"ringing","number":"+98912…","name":"Sara"}`: sent on every change. `state` is `ringing` (incoming), `dialing` (outgoing, not answered yet), `active`, or `idle` (no call). `number` and `name` may be missing.

Mac → phone:

- `{"t":"call.answer"}`: answer the ringing call.
- `{"t":"call.end"}`: decline a ringing call, or hang up.
- `{"t":"call.dial","number":"+98912…"}`: place a call from the phone's default SIM.
- `{"t":"call.error","error":"…"}` (phone → Mac): a call permission is missing, or Android refused.

## Mac to Chrome

The Mac app serves the streams on `http://127.0.0.1:8737` for the Chrome extension:

- `GET /video?camera=front|back`
- `GET /audio`

Each response streams a 4-byte codec id (`h264` or `opus`), then 12-byte packet headers, the same framing scrcpy 5 uses:

- Header with the top bit set: session packet with no payload. Its first u32 is `0x80000000 | rotation` (rotation in degrees: 0, 90, 180, 270), followed by width u32 and height u32 of the frames as sent, before turning.
- Otherwise `[pts u64][size u32]` then the payload. Bit 62 of the pts field = config, bit 61 = key frame.
