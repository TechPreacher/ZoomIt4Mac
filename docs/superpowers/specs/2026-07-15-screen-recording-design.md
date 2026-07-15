# ZoomIt4Mac Screen Recording — Design

Date: 2026-07-15
Status: Approved (brainstorming complete)
Branch: `feature/screen-recording` (off `main` @ 6af1f12)

## Goal

Screen Recording (`⌃5`): record the active display — including ZoomIt4Mac's own zoom/draw/type activity — to an .mp4, with independent toggles for microphone and system-audio capture.

## Decisions

| Topic | Decision |
|---|---|
| Default hotkey | ⌃5 (keyCode 23), rebindable; toggles start/stop |
| Start notice | ⌃5 first shows a centered HUD ("recording is starting… press ⌃5 again to stop", live combo label) for 2 s, then capture begins — the notice is never part of the video. ⌃5 during the notice cancels. Machine models this as `RecordingPhase` off → pending → active (`isRecording` = active only); effects `.showRecordingNotice`/`.dismissRecordingNotice`, event `.recordingNoticeElapsed` from a shell timer |
| Concurrency | Recording is orthogonal to modes — record while zooming/drawing/typing/breaking; Esc and mode changes never stop it |
| Audio | Two independent settings toggles: microphone (default ON) and system audio (default OFF); both mixed into the file |
| Microphone on macOS 14 | Separate `AVCaptureSession` audio pipeline (SCK gains mic capture only in macOS 15); `NSMicrophoneUsageDescription` + mic TCC prompt on first mic-enabled recording; denial degrades to recording without mic (beep + log), never blocks |
| Save flow | Auto-save to `~/Movies/ZoomIt4Mac/Recording <date> at <time>.mp4`, then Finder reveals the file. No save panel |
| Capture scope | Active display (display containing the mouse at start); annotations/zoom overlays ARE captured |
| Overlay capturability | Overlay windows become permanently `sharingType = .readOnly`; Live Zoom's explicit `SCContentFilter(excludingWindows:)` becomes the real feedback-loop protection (it currently matches nothing) |
| Format | .mp4, H.264 video @ 30 fps native pixel size, AAC audio |
| Indicator | Status item switches to a red `record.circle` while recording; menu item text toggles Start/Stop Recording |

## Core (`ZoomItCore`)

- **`HotkeyAction.toggleRecord`** — raw `toggleRecord`; default ⌃5 = KeyCombo(keyCode: 23, .control); defaults stay conflict-free.
- **`RecordingConfiguration`** (Codable, on `Settings.recording`): `recordMicrophone: Bool` (default true), `recordSystemAudio: Bool` (default false). `Settings` migration: `decodeIfPresent ?? .default` (same pattern as `breakTimer`), pinned by a strip-the-key test. No sanitization needed (booleans).
- **`SessionStateMachine.isRecording: Bool`** (read-only public, default false) — orthogonal to `state`. Handled pre-dispatch (alongside settingsChanged/displayConfigurationChanged):
  - `hotkey(.toggleRecord, _, _)` in ANY state: flips the flag; emits `[.startRecording]` or `[.stopRecording]`. Does not touch `state`. (The event is consumed pre-dispatch — it never reaches per-state handlers, so it exits no mode.)
  - `.recordingFailed` event: if recording, clears the flag and returns `[.notifyCaptureFailure]`; otherwise ignored.
  - `displayConfigurationChanged`: in addition to the existing mode force-exit, if recording, clears the flag and prepends `.stopRecording` to the returned effects (stop-and-save, not discard).
  - All other events leave `isRecording` untouched — mode entry/exit while recording is the normal, tested path.
- **Effects:** `.startRecording`, `.stopRecording`.

## Shell

- **`ScreenRecorderController`** (new file), behind `protocol ScreenRecording` (@MainActor, enables fakes):
  - `func start(displayID: CGDirectDisplayID, microphone: Bool, systemAudio: Bool, onError: @escaping @MainActor (CaptureFailure) -> Void)`
  - `func stop(completion: @escaping @MainActor (URL?) -> Void)` — finalizes the writer, returns the file URL (nil if nothing written)
  - Implementation: `SCStream` (`SCContentFilter(display:excludingWindows: [])` — excludes nothing), `SCStreamConfiguration` with native pixel size, `minimumFrameInterval` 1/30, `capturesAudio` = systemAudio flag, cursor shown; screen + audio `SCStreamOutput`s append CMSampleBuffers to an `AVAssetWriter` (.mp4, H.264, AAC). Writer session starts at the first video buffer's PTS.
  - Microphone: when enabled and authorized, an `AVCaptureSession` (default audio device → `AVCaptureAudioDataOutput`) feeds a second AAC audio input. Authorization: `AVCaptureDevice.requestAccess(.audio)` before start when status is `.notDetermined`; `.denied/.restricted` → proceed without mic, `NSSound.beep()` + log.
  - Generation-token guard against stale async completions (same pattern as `LiveStreamController`); `SCStreamDelegate.stream(_:didStopWithError:)` → salvage-finalize the file, then `onError(.captureError)`.
  - Output directory `~/Movies/ZoomIt4Mac/` created on demand; filename `Recording yyyy-MM-dd at HH.mm.ss.mp4`.
- **Coordinator:**
  - Injects `ScreenRecording` (AppDelegate passes `ScreenRecorderController()`).
  - `.startRecording` effect: Screen Recording permission preflight (missing → deferred requestPermission + `send(.recordingFailed)` — same pattern as live zoom); resolves active display; reads `machine.settings.recording` toggles; starts recorder; sets status-item indicator.
  - `.stopRecording` effect: `recorder.stop` → on URL, `NSWorkspace.shared.activateFileViewerSelecting([url])`; clears indicator.
  - `onError` → `send(.recordingFailed)`.
  - Status indicator: `StatusItemController.setRecording(_ on: Bool)` — red `record.circle` image variant; composes with the existing warning badge (warning wins). The coordinator syncs the indicator (and the menu item title) from `machine.isRecording` at the tail of every `send(_:)` — same pattern as the break tick-timer sync — so every path that flips the flag (toggle, failure, display change) updates the UI without per-path wiring.
- **Overlay change:** `OverlayWindowController` sets `sharingType = .readOnly` (was `.none`). `LiveStreamController`'s excluding-windows comment rewritten: the explicit exclusion list is now the active feedback-loop protection for live zoom.
- **Menu:** "Start Recording" / "Stop Recording" (title switches with state) after Break Timer, key "5". **Settings:** new "Recording" section — microphone toggle (with "macOS will ask for microphone access" caption), system-audio toggle. **Shortcuts panel:** Global row (⌃5 toggles recording). **README:** feature bullet + permissions note (mic optional).

## Error handling

- Screen Recording permission missing at ⌃5: deferred system prompt + guidance alert (existing pattern); machine flag flips back via `.recordingFailed`.
- Mic permission denied: record proceeds without mic audio; beep + log. Never blocks or alerts mid-recording.
- Stream/writer error mid-recording: salvage-finalize (whatever frames were written stay on disk), `.recordingFailed` clears state, beep + log; partial file still revealed if non-empty.
- Display disconnect: `displayConfigurationChanged` → stop-and-save (not discard) + modes exit as today.
- Disk-full / writer-append failures surface as the stream error path.

## Testing

Core (Swift Testing): ⌃5 toggles from idle/zoom/draw/type/break/liveZoom (flag + effect, state untouched); Esc/mode transitions/second-mode entry leave recording on; display change stops recording AND exits mode with correct combined effects; `.recordingFailed` clears only when recording; ⌃5 default conflict-free; `RecordingConfiguration` defaults + Settings migration.
Shell: manual smoke — record plain desktop, record while zoom+draw (annotations visible in the file), mic on/off, system audio on/off (play music), stop → Finder reveal, file plays in QuickTime; permission-missing paths.

## Out of scope

Region/window recording (full display only), pause/resume, camera overlay, per-recording quality settings, SCRecordingOutput fast-path (macOS 15+ — revisit when the deployment target moves).
