# ZoomIt4Mac Break Timer — Design

Date: 2026-07-15
Status: Approved (brainstorming complete)
Branch: `feature/break-timer` (off `feature/v1`)

## Goal

ZoomIt-parity Break Timer: `⌃3` shows a full-screen countdown for presentations breaks — configurable duration, background, position, and opacity; adjustable and pausable while running; sound and elapsed-time counting on expiry.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Full ZoomIt parity: backgrounds, 9-anchor position, opacity, elapsed-after-expiry, sound, pause/resume, live adjust |
| Default hotkey | ⌃3 (keyCode 20), rebindable like the others |
| Default duration | 10 minutes; range 1–99 minutes |
| Backgrounds | Solid black (default), faded desktop snapshot, custom image file. Faded desktop needs Screen Recording permission — missing permission falls back to solid black (never aborts the timer) |
| Architecture | Approach A: pure `BreakTimer` model + `.breakTimer` state in `SessionStateMachine`; shell drives ticks and renders |
| Other hotkeys during break | Exit break to idle only (consistent with existing cross-mode convention) |

## Core (`ZoomItCore`)

- **`BreakTimer`** struct — pure, monotonic timestamps injected (`now: TimeInterval`), no Date/Timer inside:
  - `init(duration: TimeInterval, startedAt: TimeInterval)`
  - `remaining(at:) -> TimeInterval` (0 when expired)
  - `isExpired(at:) -> Bool`, `elapsedAfterExpiry(at:) -> TimeInterval`
  - `isPaused`, `pause(at:)`, `resume(at:)` — pausing freezes remaining; multiple cycles accumulate correctly
  - `adjust(by seconds: TimeInterval, at:)` — clamps total remaining to 60…5940 s (1–99 min); adjusting an expired timer restarts the countdown from the added time
  - `static func format(_ seconds: TimeInterval) -> String` — `m:ss` / `mm:ss`; callers prefix `-` for elapsed-after-expiry display
- **Settings additions** (`BreakConfiguration`, Codable, on `Settings.break`):
  - `duration: TimeInterval` (default 600)
  - `position: BreakPosition` — 9 cases (topLeft…bottomRight, default center)
  - `opacity: CGFloat` (0.1…1.0, default 1.0, sanitized)
  - `background: BreakBackground` — `.solidBlack` / `.fadedDesktop` / `.imageFile(String)` (default solidBlack)
  - `showElapsedAfterExpiry: Bool` (default true), `playSound: Bool` (default true)
  - **Migration**: existing persisted `Settings` JSON (no `break` key) must decode — `break` decoded with default fallback; pinned by test.
- **`SessionStateMachine`**:
  - `HotkeyAction.toggleBreak` added (default combo ⌃3 / keyCode 20; `HotkeyConfiguration.default` extended; conflict detection unchanged via `allCases`)
  - State `.breakTimer(BreakContext)` — `BreakContext { timer: BreakTimer, soundPlayed: Bool, usedFallbackBackground: Bool }`
  - Entry from idle: if background is `.fadedDesktop`, reuse the capture flow — `.capturing` gains a purpose: `case capturing(CaptureTarget)` where `CaptureTarget` is `.zoom(mouse: CGPoint, screen: CGRect)` or `.breakTimer(now: TimeInterval)`; `captureCompleted` dispatches to zoom or break entry accordingly (existing zoom tests updated mechanically). For break, `captureFailed` of any kind falls back to solid black and still enters the timer (sets `usedFallbackBackground`), never aborts
  - Events: `.breakTick(now:)` (1 Hz + on entry), `.breakPauseResume(now:)` (Space), `.breakAdjust(seconds:, now:)` (↑ +60, ↓ −60, scroll ±60)
  - Expiry on tick: emit `.playExpirySound` once (if enabled); if `showElapsedAfterExpiry` keep counting up, else exit to idle + dismiss
  - Exits: Esc, right-click, `toggleBreak` again → idle + dismiss. `toggleZoom`/`toggleDraw` during break → idle + dismiss (no chaining)
  - New effect: `.playExpirySound`

## Shell

- **Rendering** — new branch in `OverlayContentView` for `.breakTimer`: background fill (black / snapshot drawn at 30% brightness overlay / NSImage aspect-fill), timer text (large rounded monospaced digits, white, configured opacity) at the configured anchor with fixed margins; after expiry `-m:ss` in system red (when counting elapsed)
- **Coordinator** — starts/stops a 1 Hz `Timer` while in `.breakTimer` (same MainActor pattern as the zoom-entry animation); routes Space/arrows/scroll in break mode; `.playExpirySound` → `NSSound(named: "Glass")`, fallback beep; image background loaded via `NSImage(contentsOfFile:)`, load failure → solid black
- **Settings window** — new "Break Timer" section: duration stepper (1–99 min), position picker (3×3 grid of radio-style buttons), opacity slider, background picker with image-file chooser (NSOpenPanel, png/jpeg/heic), toggles for elapsed and sound. Hotkey recorder row for Break appears automatically via `HotkeyAction.allCases`
- **Shortcuts panel** — Global section gains the Break combo automatically; new "During a break" section: Space pause/resume, ↑/↓/scroll adjust ±1 min, Esc/right-click end
- **Menu bar** — "Break Timer" item (⌃3 display) between Draw and the separator

## Error handling

- Faded-desktop without permission: fall back to solid black, continue (no alert mid-break; Settings hints at the permission)
- Image file missing/unreadable at start: solid black fallback
- Display change during break: existing global rule (force-exit to idle) applies unchanged
- Sound load failure: `NSSound.beep()`

## Testing

Core (Swift Testing, headless):
- BreakTimer: remaining/expiry math, pause freezes time, multiple pause/resume cycles, adjust clamping at both bounds, adjust-after-expiry restarts, format edge cases (0:00, 0:59, 10:00, 99:00)
- State machine: entry (solid vs fadedDesktop capture path incl. permission fallback), tick→expiry→sound-once, elapsed counting vs auto-dismiss variants, pause/adjust event routing, all exit paths, hotkey-during-break, adjust-while-paused
- Settings: BreakConfiguration codable round-trip, sanitization (opacity/duration clamps), migration from v1 JSON without `break` key
Shell: manual smoke checklist (all backgrounds, all 9 positions, opacity, pause, adjust, expiry sound, elapsed counting, rebind)

## Out of scope

Custom sound file selection, per-display break screens (shows on all displays like other modes), time-of-day clock display after expiry.
