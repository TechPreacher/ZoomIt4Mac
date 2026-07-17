# Recording Codec & Tuned Bitrate — Design

**Date:** 2026-07-17
**Status:** Approved

## Problem

Screen Recording (⌃5) writes H.264 with no `AVVideoCompressionPropertiesKey`, so
VideoToolbox picks a default bitrate that scales with pixel count. On a Retina
full-screen recording that default is very generous (tens of Mbps) — a 30-second
recording is roughly 2× the size of the same recording made with SnagIt, with no
visible quality benefit for screen content.

## Goal

Cut recording file size ~40–50% without visible quality loss, and give users a
compatibility escape hatch:

- **HEVC** (default): ~40–50% smaller at equal visual quality. Hardware-encoded
  on every Mac that can run macOS 14 (the app's deployment target), so no CPU
  cost. Caveat: Windows players may need an HEVC codec installed.
- **H.264** (option): universal playback, still significantly smaller than today
  via an explicit screen-content-tuned bitrate.

Both codecs get tuned compression properties; the user only picks the codec.
No quality-level control (YAGNI — declined during design).

## Design

### Core (`ZoomItCore`)

**`RecordingCodec`** — new enum in `RecordingConfiguration.swift`:

```swift
public enum RecordingCodec: String, Codable, Equatable, Sendable {
    case hevc
    case h264
}
```

**`RecordingConfiguration.codec`** — new field, default `.hevc`. The struct
currently uses synthesized Codable; it gains explicit `CodingKeys` and
`init(from:)` with `decodeIfPresent` for `codec` so persisted JSON from
earlier versions (no `codec` key) migrates to `.hevc`. Pinned migration test,
matching the existing `Settings` migration pattern.

**Bitrate function** — pure, testable, no AppKit. Screen content (flat regions,
static areas, sharp edges) compresses far better than camera video, so tuned
bits-per-pixel targets stay crisp:

```swift
extension RecordingCodec {
    /// Average bitrate for screen-content encoding at the given frame rate.
    /// H.264 ≈ 0.07 bpp, HEVC ≈ 0.04 bpp; floor 1 Mbps.
    public func averageBitRate(width: Int, height: Int, frameRate: Int) -> Int
}
```

Reference points at 30 fps on a 16″ MacBook Pro full screen (3456×2234):
H.264 ≈ 16 Mbps, HEVC ≈ 9 Mbps.

### Shell (`ZoomIt4Mac`)

**`RecordingWriter`** — `init` takes the codec; video settings become:

- `AVVideoCodecKey`: `.hevc` or `.h264` per setting
- `AVVideoCompressionPropertiesKey`:
  - `AVVideoAverageBitRateKey` from the core bitrate function
  - `AVVideoExpectedSourceFrameRateKey: 30` (matches the stream's
    `minimumFrameInterval`)
  - `AVVideoMaxKeyFrameIntervalKey: 60` (2-second keyframes)
  - H.264 only: `AVVideoProfileLevelKey` = High auto-level

Container stays `.mp4` for both codecs; AVFoundation writes HEVC with the
`hvc1` tag, so QuickTime/Photos/Finder previews work unchanged.

**`ScreenRecording` protocol / `ScreenRecorderController.start(...)`** — gains a
codec parameter; `SessionCoordinator` passes `settings.recording.codec` where it
already passes mic/system-audio flags.

### UI

SettingsWindow, recording section: picker **“Video codec”** with options
**HEVC (smaller files)** and **H.264 (most compatible)**, bound to
`settings.recording.codec` like the existing recording toggles.

## Error handling

No new failure modes. HEVC hardware encode is guaranteed on all macOS 14
hardware; `AVAssetWriter` init failure follows the existing throw path.

## Testing

- **Core:** migration test (recording JSON without `codec` → `.hevc`), settings
  roundtrip with explicit codec, bitrate function values (both codecs, floor
  clamping, exact expected integers).
- **Shell:** build + interactive smoke — 30 s full-screen recording per codec;
  verify HEVC file is roughly half the size of a pre-change recording, H.264
  is also smaller than before, and both play in QuickTime with audio intact.

## Out of scope

- Quality-level control (Low/Medium/High)
- Frame-rate setting (stays 30 fps)
- Container format changes
