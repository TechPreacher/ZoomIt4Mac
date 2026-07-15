# ZoomIt4Mac Live Zoom — Design

Date: 2026-07-15
Status: Approved (brainstorming complete)
Branch: `feature/live-zoom` (off `main` @ 45fb271)

## Goal

Live Zoom (`⌃4`): magnified view where the screen keeps updating (video, demos, animations) — the live counterpart to the existing frozen-snapshot Zoom, sharing its pan/zoom interaction model.

## Decisions

| Topic | Decision |
|---|---|
| Default hotkey | ⌃4 (keyCode 21), rebindable like the others |
| Displays | Active display only (display containing the mouse at trigger); other displays untouched and usable; one `SCStream` |
| Draw interop | Freeze-then-draw: left-click or ⌃2 freezes the latest live frame into the existing draw-on-zoom mode; Esc from that draw returns to live zoom |
| Rendering | `SCStream` frames (IOSurface) into a `CALayer`'s contents; zoom/pan via container-layer `CGAffineTransform` from the existing `ZoomGeometry` math — no per-frame CPU image conversion |
| Frame rate | Fixed 30 fps (`minimumFrameInterval` = 1/30); no setting (YAGNI) |
| Feedback loops | `SCContentFilter(display:excludingWindows:)` excludes our own overlay windows from the stream |
| Permission | Screen Recording required (same as frozen zoom); preflight in shell before starting; missing → existing guidance alert, no mode entered |

## Core (`ZoomItCore`)

- **`HotkeyAction.toggleLiveZoom`** — raw `toggleLiveZoom`; `HotkeyConfiguration.default` gains ⌃4 = KeyCombo(keyCode: 21, .control); conflict detection unchanged via `allCases`.
- **State `.liveZoom(ZoomContext)`** — reuses `ZoomContext` (level/mouse/screen).
- **`DrawContext.fromLiveZoom: Bool`** (default false) — routes draw-exit back to live.
- **Events:** `.liveFrameFrozen` (shell confirms the freeze frame is installed as the snapshot), `.liveStreamFailed(CaptureFailure)` (stream setup/runtime failure, reason attached — reuses the existing `CaptureFailure` enum).
- **Effects:** `.startLiveStream`, `.stopLiveStream`, `.freezeLiveFrame`.
- **Transitions:**
  - idle + `hotkey(.toggleLiveZoom, mouse, screen)` → `.liveZoom(ZoomContext(level: settings.defaultZoomLevel, mouse, screen))`, effects `[.showOverlays, .startLiveStream, .render]`. Overlays are shown before the stream starts so the stream filter can exclude the overlay windows. No async gate — the overlay shows black until the first frame arrives (~1 frame at 30 fps).
  - `.liveZoom` interactions mirror `.zoom`: `zoomChanged` (clamped 1×–8×), `mouseMoved` pan — both `[.render]`.
  - `.liveZoom` + `leftMouseDown` or `hotkey(.toggleDraw)` → state unchanged, effects `[.freezeLiveFrame]`. Shell converts the latest frame to CGImage, installs it as the display's snapshot, then sends `.liveFrameFrozen`.
  - `.liveZoom` + `.liveFrameFrozen` → `.draw(DrawContext(canvas: settings pen, zoom: ctx, fromLiveZoom: true))`, effects `[.stopLiveStream, .render]`.
  - `.liveZoom` + `.liveStreamFailed(.permissionDenied)` → idle, effects `[.stopLiveStream, .dismissOverlays, .showPermissionGuidance]`; `.liveStreamFailed(.captureError)` → idle, effects `[.stopLiveStream, .dismissOverlays, .notifyCaptureFailure]`.
  - Draw with `fromLiveZoom` + Esc/`hotkey(.toggleDraw)` → `.liveZoom(ctx.zoom!)`, effects `[.startLiveStream, .render]` (annotations discarded, consistent with frozen-zoom draw exit).
  - Exits from `.liveZoom` (Esc, right-click, `toggleLiveZoom` again, any other hotkey, `breakRequested`) → idle, effects `[.stopLiveStream, .dismissOverlays]`.
  - `displayConfigurationChanged` (global pre-dispatch) → idle + `[.dismissOverlays]` — the machine additionally emits `.stopLiveStream` first when leaving `.liveZoom` (pre-dispatch handler becomes state-aware for this one case).
  - `.liveFrameFrozen`/`.liveStreamFailed` outside `.liveZoom` → ignored (no effects).

## Shell

- **`LiveStreamController`** (new file), behind `protocol LiveStreaming` (coordinator-facing, enables fakes):
  - `func start(displayID: CGDirectDisplayID, excluding windows: [NSWindow], onFrame: @escaping @MainActor (IOSurface) -> Void) async throws`
  - `func stop()`
  - `func latestFrameImage() -> CGImage?` — converts the most recent IOSurface once (freeze path only)
  - Implementation: `SCShareableContent` → `SCContentFilter(display:excludingWindows:)`, `SCStreamConfiguration` (native pixel size, `minimumFrameInterval` = 1/30, `queueDepth` 3, cursor shown), `SCStreamOutput` on a serial queue hopping frames to MainActor.
  - Runtime stream error or zero frames → coordinator sends `.liveStreamFailed`.
- **Coordinator:** permission preflight before `.startLiveStream` executes (missing → `showGuidanceAlert()` + send `.liveStreamFailed`); effect handlers for start/stop/freeze; freeze installs `latestFrameImage()` into `snapshots[displayID]` then sends `.liveFrameFrozen` (freeze with no frame yet → treat as `.liveStreamFailed`); input routing mirrors zoom for `.liveZoom` (scroll/pinch/arrows/mouseMoved).
- **Overlay:** created only for the active display in live mode (existing `showOverlays()` gains a live-mode branch). `OverlayContentView` hosts a layer-backed `liveContainerLayer` whose sublayer receives IOSurface frames; on each `render` with `.liveZoom` state the container's `CGAffineTransform` is recomputed from `ZoomGeometry.visibleRect` (same formula as the frozen-zoom draw transform). The layer is torn down on leaving live mode.
- **Menu bar:** "Live Zoom" item (⌃4 display) after Zoom. **Shortcuts panel:** Global row + note that zoom-mode keys apply while live; freeze-to-draw row. **Settings:** hotkey recorder row appears via `allCases`. **README:** feature bullet.

## Error handling

- Permission missing at trigger: guidance alert (reuses PermissionCoordinator), no mode entered.
- Stream fails mid-session (display disconnect, SCK error): `.liveStreamFailed` → idle + dismiss (guidance alert only when permission is actually missing; otherwise beep + log).
- Freeze requested before first frame: treated as stream failure (exit cleanly).
- Display change during live: global rule exits to idle; stream stopped.

## Testing

Core (Swift Testing): entry transition + effect order; all interaction events mirror zoom (clamp, pan); freeze round-trip (`leftMouseDown` → `.freezeLiveFrame` → `.liveFrameFrozen` → draw with `fromLiveZoom`, `.stopLiveStream` emitted); Esc-from-draw returns to live with `.startLiveStream`; all exit paths emit `.stopLiveStream`; `.liveStreamFailed` handling; events ignored outside `.liveZoom`; ⌃4 default conflict-free; `DrawContext.fromLiveZoom` defaults false (existing draw tests unaffected).
Shell: manual smoke — video keeps playing while zoomed, pan/zoom smooth, freeze→draw→Esc→live round-trip, permission fallback, menu/shortcuts/settings rows.

## Out of scope

Multi-display live streaming, live-zoom frame-rate setting, drawing directly on the live stream (freeze is the path), audio.
