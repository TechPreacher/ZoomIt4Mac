# Break Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ZoomIt-parity Break Timer (⌃3): full-screen countdown with configurable duration/background/position/opacity, live adjust, pause/resume, sound and elapsed counting on expiry.

**Architecture:** Pure `BreakTimer` model + `.breakTimer` state in `SessionStateMachine` (ZoomItCore); shell drives 1 Hz ticks with injected monotonic timestamps and renders in `OverlayContentView`. `.capturing` gains a `CaptureTarget` so the faded-desktop background reuses the existing snapshot flow. Spec: `docs/superpowers/specs/2026-07-15-break-timer-design.md`.

**Tech Stack:** Swift 6, existing v1 stack (AppKit shell, SwiftUI settings, Swift Testing).

## Global Constraints

- Branch: `feature/break-timer`. All existing 85 tests must stay green (some `.capturing` tests are updated mechanically in Task 3 — count grows, never shrinks).
- ZoomItCore never imports AppKit; core tests headless (no Date/Timer in core — timestamps injected).
- Default break hotkey: **⌃3 (keyCode 20, .control)**. Duration default **600 s**, clamp **60…5940 s** (1–99 min). Opacity clamp **0.1…1.0**, default 1.0.
- Old persisted Settings JSON (no `breakTimer` key) must decode to defaults — pinned by test.
- Faded-desktop capture failure (any reason) falls back to solid black and still starts the timer — never aborts, no alert.
- Commits: descriptive, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Test command: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`. New files → run `xcodegen` first.

## File Structure

```
ZoomItCore/Sources/BreakTimer.swift            countdown model (new)
ZoomItCore/Sources/BreakConfiguration.swift    settings sub-struct + enums (new)
ZoomItCore/Sources/Settings.swift              gains breakTimer field + migration (modify)
ZoomItCore/Sources/SessionStateMachine.swift   CaptureTarget, .breakTimer state, events/effects (modify)
ZoomItCore/Tests/BreakTimerTests.swift         (new)
ZoomItCore/Tests/BreakConfigurationTests.swift (new)
ZoomItCore/Tests/SessionStateMachineTests.swift  break suites appended, capturing tests updated (modify)
ZoomItCore/Tests/SettingsTests.swift           migration test appended (modify)
ZoomIt4Mac/Sources/SessionCoordinator.swift    tick timer, break input, sound, image loading (modify)
ZoomIt4Mac/Sources/OverlayContentView.swift    break rendering (modify)
ZoomIt4Mac/Sources/OverlayWindowController.swift  breakImage passthrough (modify)
ZoomIt4Mac/Sources/StatusItemController.swift  Break Timer menu item (modify)
ZoomIt4Mac/Sources/SettingsWindow.swift        Break Timer section + hotkey row (modify)
ZoomIt4Mac/Sources/ShortcutsWindow.swift       break shortcuts (modify)
README.md                                      feature docs (modify)
```

---

### Task 1: BreakTimer model

**Files:**
- Create: `ZoomItCore/Sources/BreakTimer.swift`
- Test: `ZoomItCore/Tests/BreakTimerTests.swift`

**Interfaces:**
- Produces `BreakTimer: Equatable, Sendable`:
  - `static let minTotal: TimeInterval = 60`, `static let maxTotal: TimeInterval = 5940`
  - `init(duration: TimeInterval, startedAt now: TimeInterval)` — duration clamped to 60…5940
  - `isPaused: Bool` (read-only)
  - `func remaining(at now: TimeInterval) -> TimeInterval` — 0 floor; frozen while paused
  - `func isExpired(at now: TimeInterval) -> Bool` — remaining == 0 and not paused
  - `func elapsedAfterExpiry(at now: TimeInterval) -> TimeInterval` — 0 until expired
  - `mutating func pause(at now: TimeInterval)` / `mutating func resume(at now: TimeInterval)` — no-ops if already in that mode; cycles accumulate correctly
  - `mutating func adjust(by seconds: TimeInterval, at now: TimeInterval)` — new remaining clamped 60…5940; works paused or running or expired (expired+adjust restarts countdown)
  - `static func format(_ seconds: TimeInterval) -> String` — ceiling to whole seconds, `m:ss` / `mm:ss` (no leading zero on minutes)

- [ ] **Step 1: Write the failing test**

`ZoomItCore/Tests/BreakTimerTests.swift`:
```swift
import Testing
import Foundation
import ZoomItCore

struct BreakTimerTests {
    @Test func countsDownFromDuration() {
        let t = BreakTimer(duration: 600, startedAt: 1000)
        #expect(t.remaining(at: 1000) == 600)
        #expect(t.remaining(at: 1300) == 300)
        #expect(t.remaining(at: 1600) == 0)
        #expect(t.remaining(at: 2000) == 0) // floored at zero
    }

    @Test func initClampsDuration() {
        #expect(BreakTimer(duration: 5, startedAt: 0).remaining(at: 0) == 60)
        #expect(BreakTimer(duration: 100_000, startedAt: 0).remaining(at: 0) == 5940)
    }

    @Test func expiryAndElapsed() {
        let t = BreakTimer(duration: 60, startedAt: 0)
        #expect(!t.isExpired(at: 59))
        #expect(t.isExpired(at: 60))
        #expect(t.elapsedAfterExpiry(at: 59) == 0)
        #expect(t.elapsedAfterExpiry(at: 90) == 30)
    }

    @Test func pauseFreezesRemaining() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        #expect(t.isPaused)
        #expect(t.remaining(at: 100) == 500)
        #expect(t.remaining(at: 9999) == 500) // frozen
        #expect(!t.isExpired(at: 9999))       // paused timer never expires
        t.resume(at: 200)
        #expect(!t.isPaused)
        #expect(t.remaining(at: 200) == 500)
        #expect(t.remaining(at: 300) == 400)
    }

    @Test func multiplePauseResumeCyclesAccumulate() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)   // 500 left
        t.resume(at: 150)
        t.pause(at: 250)   // ran 100 more, 400 left
        t.resume(at: 1000)
        #expect(t.remaining(at: 1100) == 300)
    }

    @Test func pauseWhenPausedIsNoOp() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        t.pause(at: 200)
        #expect(t.remaining(at: 300) == 500)
        var s = BreakTimer(duration: 600, startedAt: 0)
        s.resume(at: 100) // resume while running: no-op
        #expect(s.remaining(at: 200) == 400)
    }

    @Test func adjustAddsAndClamps() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.adjust(by: 60, at: 100)
        #expect(t.remaining(at: 100) == 560)
        t.adjust(by: -100_000, at: 100)
        #expect(t.remaining(at: 100) == 60)   // clamped low
        t.adjust(by: 100_000, at: 100)
        #expect(t.remaining(at: 100) == 5940) // clamped high
    }

    @Test func adjustAfterExpiryRestartsCountdown() {
        var t = BreakTimer(duration: 60, startedAt: 0)
        #expect(t.isExpired(at: 120))
        t.adjust(by: 60, at: 120)
        #expect(!t.isExpired(at: 120))
        #expect(t.remaining(at: 120) == 60)
        #expect(t.elapsedAfterExpiry(at: 120) == 0)
    }

    @Test func adjustWhilePaused() {
        var t = BreakTimer(duration: 600, startedAt: 0)
        t.pause(at: 100)
        t.adjust(by: 60, at: 500)
        #expect(t.isPaused)
        #expect(t.remaining(at: 999) == 560)
    }

    @Test func formatEdgeCases() {
        #expect(BreakTimer.format(0) == "0:00")
        #expect(BreakTimer.format(59) == "0:59")
        #expect(BreakTimer.format(60) == "1:00")
        #expect(BreakTimer.format(600) == "10:00")
        #expect(BreakTimer.format(5940) == "99:00")
        #expect(BreakTimer.format(59.4) == "1:00") // ceiling: countdown shows 1:00 until it hits 0:59
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BreakTimer' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ZoomItCore/Sources/BreakTimer.swift`:
```swift
import Foundation

/// Pure countdown model. All time is injected as monotonic timestamps so the
/// model is deterministic and testable; the shell supplies CACurrentMediaTime().
public struct BreakTimer: Equatable, Sendable {
    public static let minTotal: TimeInterval = 60
    public static let maxTotal: TimeInterval = 5940

    /// Absolute end timestamp while running; meaningless while paused.
    private var endTime: TimeInterval
    /// Non-nil while paused: the frozen remaining time.
    private var pausedRemaining: TimeInterval?

    public var isPaused: Bool { pausedRemaining != nil }

    public init(duration: TimeInterval, startedAt now: TimeInterval) {
        let clamped = min(max(duration, Self.minTotal), Self.maxTotal)
        self.endTime = now + clamped
        self.pausedRemaining = nil
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, endTime - now)
    }

    public func isExpired(at now: TimeInterval) -> Bool {
        !isPaused && remaining(at: now) == 0
    }

    public func elapsedAfterExpiry(at now: TimeInterval) -> TimeInterval {
        guard isExpired(at: now) else { return 0 }
        return now - endTime
    }

    public mutating func pause(at now: TimeInterval) {
        guard !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: TimeInterval) {
        guard let frozen = pausedRemaining else { return }
        endTime = now + frozen
        pausedRemaining = nil
    }

    public mutating func adjust(by seconds: TimeInterval, at now: TimeInterval) {
        let target = min(max(remaining(at: now) + seconds, Self.minTotal), Self.maxTotal)
        if isPaused {
            pausedRemaining = target
        } else {
            endTime = now + target
        }
    }

    /// Ceiling to whole seconds so a countdown reads 1:00 until it reaches 0:59.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore
git commit -m "Add BreakTimer countdown model"
```

---

### Task 2: BreakConfiguration + Settings migration

**Files:**
- Create: `ZoomItCore/Sources/BreakConfiguration.swift`
- Modify: `ZoomItCore/Sources/Settings.swift`
- Test: `ZoomItCore/Tests/BreakConfigurationTests.swift` (new), `ZoomItCore/Tests/SettingsTests.swift` (append)

**Interfaces:**
- Produces:
  - `BreakPosition: String, Codable, CaseIterable, Equatable, Sendable` — cases `topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight`
  - `BreakBackground: Codable, Equatable, Sendable` — cases `solidBlack`, `fadedDesktop`, `imageFile(String)`
  - `BreakConfiguration: Codable, Equatable, Sendable` — `duration: TimeInterval` (600), `position: BreakPosition` (.center), `opacity: CGFloat` (1.0), `background: BreakBackground` (.solidBlack), `showElapsedAfterExpiry: Bool` (true), `playSound: Bool` (true); `static let default`; `func sanitized() -> BreakConfiguration` (duration 60…5940, opacity 0.1…1.0)
  - `Settings.breakTimer: BreakConfiguration` — decodes to `.default` when the key is missing (v1 JSON migration); `Settings.sanitized()` also sanitizes `breakTimer`

- [ ] **Step 1: Write the failing test**

`ZoomItCore/Tests/BreakConfigurationTests.swift`:
```swift
import Testing
import Foundation
import ZoomItCore

struct BreakConfigurationTests {
    @Test func defaults() {
        let c = BreakConfiguration.default
        #expect(c.duration == 600)
        #expect(c.position == .center)
        #expect(c.opacity == 1.0)
        #expect(c.background == .solidBlack)
        #expect(c.showElapsedAfterExpiry)
        #expect(c.playSound)
    }

    @Test func sanitizeClampsDurationAndOpacity() {
        var c = BreakConfiguration.default
        c.duration = 5
        c.opacity = 7
        let s = c.sanitized()
        #expect(s.duration == 60)
        #expect(s.opacity == 1.0)
        c.duration = 999_999
        c.opacity = 0
        let s2 = c.sanitized()
        #expect(s2.duration == 5940)
        #expect(s2.opacity == 0.1)
    }

    @Test func codableRoundTripAllBackgrounds() throws {
        for background in [BreakBackground.solidBlack, .fadedDesktop, .imageFile("/tmp/pic.png")] {
            var c = BreakConfiguration.default
            c.background = background
            c.position = .bottomRight
            let data = try JSONEncoder().encode(c)
            let back = try JSONDecoder().decode(BreakConfiguration.self, from: data)
            #expect(back == c)
        }
    }

    @Test func positionHasNineCases() {
        #expect(BreakPosition.allCases.count == 9)
    }
}
```

Append to `ZoomItCore/Tests/SettingsTests.swift`:
```swift
struct SettingsBreakMigrationTests {
    @Test func v1JSONWithoutBreakKeyDecodesToDefaults() throws {
        // Persisted by the v1 app: no breakTimer field existed.
        let store = SettingsStore(persistence: FakePersistence())
        var v1 = Settings.default
        v1.penColor = .green
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(v1)) as! [String: Any]
        object.removeValue(forKey: "breakTimer")
        let v1Data = try JSONSerialization.data(withJSONObject: object)

        let p = FakePersistence()
        p.storage["zoomit.settings.v1"] = v1Data
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.penColor == .green)               // old fields preserved
        #expect(loaded.breakTimer == .default)           // new field defaulted
        _ = store // silence unused warning
    }

    @Test func breakConfigSanitizedOnLoad() throws {
        let p = FakePersistence()
        var s = Settings.default
        s.breakTimer.duration = 1
        p.storage["zoomit.settings.v1"] = try JSONEncoder().encode(s)
        let loaded = SettingsStore(persistence: p).load()
        #expect(loaded.breakTimer.duration == 60)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BreakConfiguration' in scope`.

- [ ] **Step 3: Write minimal implementation**

`ZoomItCore/Sources/BreakConfiguration.swift`:
```swift
import CoreGraphics
import Foundation

public enum BreakPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
}

public enum BreakBackground: Codable, Equatable, Sendable {
    case solidBlack
    case fadedDesktop
    case imageFile(String)
}

public struct BreakConfiguration: Codable, Equatable, Sendable {
    public var duration: TimeInterval
    public var position: BreakPosition
    public var opacity: CGFloat
    public var background: BreakBackground
    public var showElapsedAfterExpiry: Bool
    public var playSound: Bool

    public static let `default` = BreakConfiguration(
        duration: 600,
        position: .center,
        opacity: 1.0,
        background: .solidBlack,
        showElapsedAfterExpiry: true,
        playSound: true
    )

    public func sanitized() -> BreakConfiguration {
        var c = self
        c.duration = min(max(duration.isFinite ? duration : 600, BreakTimer.minTotal), BreakTimer.maxTotal)
        c.opacity = min(max(opacity.isFinite ? opacity : 1.0, 0.1), 1.0)
        return c
    }
}
```

In `ZoomItCore/Sources/Settings.swift`, add the field, a custom decoder for migration, and extend `sanitized()`:
```swift
public struct Settings: Codable, Equatable, Sendable {
    public var hotkeys: HotkeyConfiguration
    public var defaultZoomLevel: CGFloat
    public var penColor: AnnotationColor
    public var penWidth: CGFloat
    public var breakTimer: BreakConfiguration

    public static let `default` = Settings(
        hotkeys: .default,
        defaultZoomLevel: 2.0,
        penColor: .red,
        penWidth: 4,
        breakTimer: .default
    )

    public init(
        hotkeys: HotkeyConfiguration,
        defaultZoomLevel: CGFloat,
        penColor: AnnotationColor,
        penWidth: CGFloat,
        breakTimer: BreakConfiguration
    ) {
        self.hotkeys = hotkeys
        self.defaultZoomLevel = defaultZoomLevel
        self.penColor = penColor
        self.penWidth = penWidth
        self.breakTimer = breakTimer
    }

    // Migration: v1 persisted JSON has no breakTimer key.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try container.decode(HotkeyConfiguration.self, forKey: .hotkeys)
        defaultZoomLevel = try container.decode(CGFloat.self, forKey: .defaultZoomLevel)
        penColor = try container.decode(AnnotationColor.self, forKey: .penColor)
        penWidth = try container.decode(CGFloat.self, forKey: .penWidth)
        breakTimer = try container.decodeIfPresent(BreakConfiguration.self, forKey: .breakTimer) ?? .default
    }

    public func sanitized() -> Settings {
        var s = self
        s.defaultZoomLevel = ZoomGeometry.clamp(defaultZoomLevel)
        s.penWidth = AnnotationCanvas.clampWidth(penWidth)
        s.breakTimer = breakTimer.sanitized()
        return s
    }
}
```
(The memberwise init must become explicit because the custom `init(from:)` suppresses it. `CodingKeys` stays synthesized.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED (all prior suites green — `Settings.default` construction sites in tests are unaffected because the static `.default` still exists).

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore
git commit -m "Add break timer configuration to settings with v1 migration"
```

---

### Task 3: State machine — break entry/exit + CaptureTarget

**Files:**
- Modify: `ZoomItCore/Sources/SessionStateMachine.swift`, `ZoomIt4Mac/Sources/SessionCoordinator.swift` (one mechanical site), `ZoomItCore/Tests/SessionStateMachineTests.swift` (update capturing tests + append)
- Modify: `ZoomItCore/Sources/HotkeyConfiguration.swift` (add toggleBreak default)

**Interfaces:**
- Produces:
  - `HotkeyAction.toggleBreak` (String raw `toggleBreak`); `HotkeyConfiguration.default` gains `⌃3` = KeyCombo(keyCode: 20, modifiers: .control)
  - `CaptureTarget: Equatable, Sendable` — `case zoom(mouse: CGPoint, screen: CGRect)`, `case breakTimer(now: TimeInterval)`
  - `SessionState.capturing(CaptureTarget)` (replaces `capturing(mouse:screen:)`)
  - `BreakContext: Equatable, Sendable` — `init(timer: BreakTimer, soundPlayed: Bool = false, usedFallbackBackground: Bool = false)`, mutable fields same names
  - `SessionState.breakTimer(BreakContext)`
  - `SessionEvent.breakRequested(now: TimeInterval)` — the coordinator maps the ⌃3 hotkey to this
  - Entry semantics: idle + breakRequested → `.breakTimer` immediately (solid/image backgrounds) or `.capturing(.breakTimer(now:))` + `[.captureScreens]` (fadedDesktop); capture failure of ANY kind → enter break with `usedFallbackBackground = true`, effects `[.showOverlays, .render]`
  - Exit semantics: escape / rightMouseAction / breakRequested / any `.hotkey` while in `.breakTimer` → idle + `[.dismissOverlays]`; breakRequested while in zoom/draw/type → idle + `[.dismissOverlays]` (type commits its run first)

- [ ] **Step 1: Update existing capturing call sites + write the failing tests**

In `ZoomItCore/Tests/SessionStateMachineTests.swift`, mechanically update the two existing assertions that construct `.capturing(mouse:screen:)`:
- In `zoomHotkeyStartsCapture`: `#expect(m.state == .capturing(.zoom(mouse: testMouse, screen: testScreen)))`
(Any other direct `.capturing(mouse:screen:)` pattern matches in tests get the same treatment: wrap in `.zoom(...)`.)

Append:
```swift
func breakMachine(_ settings: Settings = .default) -> SessionStateMachine {
    var m = machine(settings)
    m.handle(.breakRequested(now: 1000))
    return m
}

extension SessionStateMachine {
    var breakContext: BreakContext? {
        if case .breakTimer(let ctx) = state { return ctx }
        return nil
    }
}

struct SessionBreakEntryTests {
    @Test func breakRequestedEntersTimerWithSolidBackground() {
        var m = machine() // default background: solidBlack
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.showOverlays, .render])
        guard let ctx = m.breakContext else { Issue.record("expected break"); return }
        #expect(ctx.timer.remaining(at: 1000) == 600)
        #expect(!ctx.usedFallbackBackground)
        #expect(!ctx.soundPlayed)
    }

    @Test func fadedDesktopEntersCaptureFirst() {
        var settings = Settings.default
        settings.breakTimer.background = .fadedDesktop
        var m = machine(settings)
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.captureScreens])
        #expect(m.state == .capturing(.breakTimer(now: 1000)))
        let fx2 = m.handle(.captureCompleted)
        #expect(fx2 == [.showOverlays, .render])
        #expect(m.breakContext?.usedFallbackBackground == false)
    }

    @Test func captureFailureFallsBackToSolidAndStillStarts() {
        var settings = Settings.default
        settings.breakTimer.background = .fadedDesktop
        for failure in [CaptureFailure.permissionDenied, .captureError] {
            var m = machine(settings)
            m.handle(.breakRequested(now: 1000))
            let fx = m.handle(.captureFailed(failure))
            #expect(fx == [.showOverlays, .render]) // no permission guidance mid-break
            guard let ctx = m.breakContext else { Issue.record("expected break"); return }
            #expect(ctx.usedFallbackBackground)
            #expect(ctx.timer.remaining(at: 1000) == 600)
        }
    }

    @Test func zoomCaptureFailureStillShowsGuidance() {
        var m = machine()
        m.handle(.hotkey(.toggleZoom, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureFailed(.permissionDenied)) == [.showPermissionGuidance])
        #expect(m.state == .idle)
    }

    @Test func exitsOnEscapeRightClickAndToggle() {
        for event in [SessionEvent.escape, .rightMouseAction, .breakRequested(now: 2000)] {
            var m = breakMachine()
            let fx = m.handle(event)
            #expect(fx == [.dismissOverlays])
            #expect(m.state == .idle)
        }
    }

    @Test func otherHotkeysExitBreakToIdle() {
        for action in [HotkeyAction.toggleZoom, .toggleDraw] {
            var m = breakMachine()
            let fx = m.handle(.hotkey(action, mouse: testMouse, screen: testScreen))
            #expect(fx == [.dismissOverlays])
            #expect(m.state == .idle)
        }
    }

    @Test func breakRequestedDuringZoomExitsToIdle() {
        var m = zoomedMachine()
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func breakRequestedDuringTypeCommitsRunThenExits() {
        var m = drawingMachine()
        m.handle(.keyCommand(.enterType))
        m.handle(.leftMouseDown(.zero))
        m.handle(.textInput("x"))
        let fx = m.handle(.breakRequested(now: 1000))
        #expect(fx == [.dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func defaultBreakHotkeyIsCtrl3() {
        #expect(HotkeyConfiguration.default.combo(for: .toggleBreak) == KeyCombo(keyCode: 20, modifiers: .control))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `type 'HotkeyAction' has no member 'toggleBreak'` / `cannot find 'CaptureTarget'`.

- [ ] **Step 3: Write minimal implementation**

`ZoomItCore/Sources/HotkeyConfiguration.swift` — add case and default:
```swift
public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case toggleZoom, toggleDraw, toggleBreak
}
```
```swift
    public static let `default` = HotkeyConfiguration(bindings: [
        .toggleZoom: KeyCombo(keyCode: 18, modifiers: .control),  // ⌃1
        .toggleDraw: KeyCombo(keyCode: 19, modifiers: .control),  // ⌃2
        .toggleBreak: KeyCombo(keyCode: 20, modifiers: .control), // ⌃3
    ])
```

`ZoomItCore/Sources/SessionStateMachine.swift` — types:
```swift
public enum CaptureTarget: Equatable, Sendable {
    case zoom(mouse: CGPoint, screen: CGRect)
    case breakTimer(now: TimeInterval)
}

public struct BreakContext: Equatable, Sendable {
    public var timer: BreakTimer
    public var soundPlayed: Bool
    public var usedFallbackBackground: Bool

    public init(timer: BreakTimer, soundPlayed: Bool = false, usedFallbackBackground: Bool = false) {
        self.timer = timer
        self.soundPlayed = soundPlayed
        self.usedFallbackBackground = usedFallbackBackground
    }
}
```
`SessionState`: replace `case capturing(mouse: CGPoint, screen: CGRect)` with `case capturing(CaptureTarget)`; add `case breakTimer(BreakContext)`.
`SessionEvent`: add `case breakRequested(now: TimeInterval)`.

Dispatch changes in `handle(_:)`:
```swift
        switch state {
        case .idle:
            return handleIdle(event)
        case .capturing(let target):
            return handleCapturing(event, target: target)
        case .zoom(let ctx):
            return handleZoom(event, ctx)
        case .draw(let ctx):
            return handleDraw(event, ctx)
        case .type(let ctx, let tool):
            return handleType(event, ctx, tool)
        case .breakTimer(let ctx):
            return handleBreak(event, ctx)
        }
```

`handleIdle` — zoom case wraps the target; new break entry:
```swift
        case .hotkey(.toggleZoom, let mouse, let screen):
            state = .capturing(.zoom(mouse: mouse, screen: screen))
            return [.captureScreens]
        case .breakRequested(let now):
            if case .fadedDesktop = settings.breakTimer.background {
                state = .capturing(.breakTimer(now: now))
                return [.captureScreens]
            }
            return enterBreak(now: now, usedFallback: false)
```
Helper:
```swift
    private mutating func enterBreak(now: TimeInterval, usedFallback: Bool) -> [SessionEffect] {
        let timer = BreakTimer(duration: settings.breakTimer.duration, startedAt: now)
        state = .breakTimer(BreakContext(timer: timer, usedFallbackBackground: usedFallback))
        return [.showOverlays, .render]
    }
```

`handleCapturing` rewritten around the target:
```swift
    private mutating func handleCapturing(_ event: SessionEvent, target: CaptureTarget) -> [SessionEffect] {
        switch (event, target) {
        case (.captureCompleted, .zoom(let mouse, let screen)):
            state = .zoom(ZoomContext(level: settings.defaultZoomLevel, mouse: mouse, screen: screen))
            return [.showOverlays, .render]
        case (.captureCompleted, .breakTimer(let now)):
            return enterBreak(now: now, usedFallback: false)
        case (.captureFailed(.permissionDenied), .zoom):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .zoom):
            state = .idle
            return [.notifyCaptureFailure]
        case (.captureFailed, .breakTimer(let now)):
            return enterBreak(now: now, usedFallback: true)
        case (.escape, _):
            state = .idle
            return []
        default:
            return []
        }
    }
```

`handleBreak` (exits only in this task; tick/pause/adjust land in Task 4):
```swift
    private mutating func handleBreak(_ event: SessionEvent, _ ctx: BreakContext) -> [SessionEffect] {
        switch event {
        case .escape, .rightMouseAction, .breakRequested, .hotkey:
            state = .idle
            return [.dismissOverlays]
        default:
            return []
        }
    }
```

Cross-mode exits — add `.breakRequested` to the existing exit patterns:
- `handleZoom`: extend the exit case to `case .escape, .rightMouseAction, .hotkey(.toggleZoom, _, _), .breakRequested:`
- `handleDraw`: extend `case .hotkey(.toggleZoom, _, _):` to `case .hotkey(.toggleZoom, _, _), .breakRequested:`
- `handleType`: extend `case .hotkey:` to `case .hotkey, .breakRequested:` (commitRun already happens there)

`ZoomIt4Mac/Sources/SessionCoordinator.swift` — one mechanical change in `trigger(_:)`:
```swift
    func trigger(_ action: HotkeyAction) {
        if action == .toggleBreak {
            send(.breakRequested(now: CACurrentMediaTime()))
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screen(containing: mouse)?.frame
            ?? NSScreen.main?.frame ?? .zero
        send(.hotkey(action, mouse: mouse, screen: screen))
    }
```
(Needs `import QuartzCore` only if not already resolvable via AppKit — it is.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED — all suites, including the mechanically updated capturing assertions.

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore ZoomIt4Mac
git commit -m "Add break timer entry/exit to state machine with capture targets"
```

---

### Task 4: State machine — tick, expiry, pause, adjust

**Files:**
- Modify: `ZoomItCore/Sources/SessionStateMachine.swift` (extend `handleBreak`)
- Test: `ZoomItCore/Tests/SessionStateMachineTests.swift` (append)

**Interfaces:**
- Produces:
  - `SessionEvent`: `case breakTick(now: TimeInterval)`, `case breakPauseResume(now: TimeInterval)`, `case breakAdjust(seconds: TimeInterval, now: TimeInterval)`
  - `SessionEffect`: `case playExpirySound`
  - Semantics: tick renders; first expired tick sets `soundPlayed` and emits `.playExpirySound` iff `playSound`; expiry with `showElapsedAfterExpiry == false` exits (sound still emitted on that same tick when enabled); adjust that un-expires the timer clears `soundPlayed` so a later expiry sounds again

- [ ] **Step 1: Write the failing test**

Append to `ZoomItCore/Tests/SessionStateMachineTests.swift`:
```swift
struct SessionBreakRunTests {
    // breakMachine() starts a 600 s timer at now=1000 (defaults: sound on, elapsed on)

    @Test func tickRendersWhileRunning() {
        var m = breakMachine()
        #expect(m.handle(.breakTick(now: 1001)) == [.render])
        #expect(m.breakContext?.soundPlayed == false)
    }

    @Test func expiryEmitsSoundOnceThenKeepsCounting() {
        var m = breakMachine()
        #expect(m.handle(.breakTick(now: 1600)) == [.playExpirySound, .render])
        #expect(m.breakContext?.soundPlayed == true)
        #expect(m.handle(.breakTick(now: 1601)) == [.render]) // once
        guard case .breakTimer = m.state else { Issue.record("still counting elapsed"); return }
    }

    @Test func expiryWithSoundDisabledJustRenders() {
        var settings = Settings.default
        settings.breakTimer.playSound = false
        var m = breakMachine(settings)
        #expect(m.handle(.breakTick(now: 1600)) == [.render])
        #expect(m.breakContext?.soundPlayed == true) // marked so re-eval stops
    }

    @Test func expiryWithoutElapsedDisplayExits() {
        var settings = Settings.default
        settings.breakTimer.showElapsedAfterExpiry = false
        var m = breakMachine(settings)
        let fx = m.handle(.breakTick(now: 1600))
        #expect(fx == [.playExpirySound, .dismissOverlays])
        #expect(m.state == .idle)
    }

    @Test func pauseResumeToggles() {
        var m = breakMachine()
        m.handle(.breakPauseResume(now: 1100)) // pause with 500 left
        #expect(m.breakContext?.timer.isPaused == true)
        m.handle(.breakTick(now: 5000))
        #expect(m.breakContext?.timer.remaining(at: 5000) == 500)
        m.handle(.breakPauseResume(now: 5000)) // resume
        #expect(m.breakContext?.timer.isPaused == false)
        #expect(m.breakContext?.timer.remaining(at: 5100) == 400)
    }

    @Test func adjustChangesRemaining() {
        var m = breakMachine()
        #expect(m.handle(.breakAdjust(seconds: 60, now: 1000)) == [.render])
        #expect(m.breakContext?.timer.remaining(at: 1000) == 660)
        m.handle(.breakAdjust(seconds: -60, now: 1000))
        #expect(m.breakContext?.timer.remaining(at: 1000) == 600)
    }

    @Test func adjustAfterExpiryRearmsSound() {
        var m = breakMachine()
        m.handle(.breakTick(now: 1600)) // expire, sound played
        m.handle(.breakAdjust(seconds: 60, now: 1600))
        #expect(m.breakContext?.soundPlayed == false) // re-armed
        #expect(m.handle(.breakTick(now: 1660)) == [.playExpirySound, .render])
    }

    @Test func breakEventsIgnoredOutsideBreakState() {
        var m = machine()
        #expect(m.handle(.breakTick(now: 1)).isEmpty)
        #expect(m.handle(.breakPauseResume(now: 1)).isEmpty)
        #expect(m.handle(.breakAdjust(seconds: 60, now: 1)).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `type 'SessionEvent' has no member 'breakTick'`.

- [ ] **Step 3: Write minimal implementation**

Add the three events and the effect to their enums, then extend `handleBreak`:
```swift
    private mutating func handleBreak(_ event: SessionEvent, _ ctx: BreakContext) -> [SessionEffect] {
        var ctx = ctx
        switch event {
        case .escape, .rightMouseAction, .breakRequested, .hotkey:
            state = .idle
            return [.dismissOverlays]
        case .breakTick(let now):
            guard ctx.timer.isExpired(at: now), !ctx.soundPlayed else {
                state = .breakTimer(ctx)
                return [.render]
            }
            ctx.soundPlayed = true
            var effects: [SessionEffect] = []
            if settings.breakTimer.playSound { effects.append(.playExpirySound) }
            if settings.breakTimer.showElapsedAfterExpiry {
                state = .breakTimer(ctx)
                effects.append(.render)
            } else {
                state = .idle
                effects.append(.dismissOverlays)
            }
            return effects
        case .breakPauseResume(let now):
            if ctx.timer.isPaused {
                ctx.timer.resume(at: now)
            } else {
                ctx.timer.pause(at: now)
            }
            state = .breakTimer(ctx)
            return [.render]
        case .breakAdjust(let seconds, let now):
            ctx.timer.adjust(by: seconds, at: now)
            if !ctx.timer.isExpired(at: now) { ctx.soundPlayed = false }
            state = .breakTimer(ctx)
            return [.render]
        default:
            return []
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore
git commit -m "Add break timer tick, expiry, pause, and adjust behavior"
```

---

### Task 5: Shell — coordinator wiring, rendering, menu, sound

**Files:**
- Modify: `ZoomIt4Mac/Sources/SessionCoordinator.swift`, `ZoomIt4Mac/Sources/OverlayContentView.swift`, `ZoomIt4Mac/Sources/OverlayWindowController.swift`, `ZoomIt4Mac/Sources/StatusItemController.swift`, `ZoomIt4Mac/Sources/AppDelegate.swift`

Shell task: no unit tests by design; ends with build + suite regression + manual smoke.

**Interfaces:**
- Consumes: everything from Tasks 1–4
- Produces: running break timer UX; `SessionCoordinator.currentSettings() -> Settings` for the view; `OverlayWindowController.breakImage: CGImage?`

- [ ] **Step 1: Coordinator — tick timer, input routing, sound, image loading**

In `SessionCoordinator.swift`:

Add properties:
```swift
    private var breakTickTimer: Timer?
    private var breakImage: CGImage?
```

Expose settings for the render layer:
```swift
    func currentSettings() -> Settings { machine.settings }
```

At the end of `send(_:)` (next to the tabHeld reset), manage the tick timer:
```swift
        syncBreakTickTimer()
```
and add:
```swift
    private func syncBreakTickTimer() {
        let inBreak = if case .breakTimer = machine.state { true } else { false }
        if inBreak && breakTickTimer == nil {
            breakTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.send(.breakTick(now: CACurrentMediaTime()))
                }
            }
        } else if !inBreak, let timer = breakTickTimer {
            timer.invalidate()
            breakTickTimer = nil
        }
    }
```

Break-mode key routing — in `handleKeyDown(_:)`, after the Esc branch and before the type branch:
```swift
        if case .breakTimer = machine.state {
            switch event.keyCode {
            case 49: send(.breakPauseResume(now: CACurrentMediaTime())) // Space
            case 126: send(.breakAdjust(seconds: 60, now: CACurrentMediaTime()))  // ↑
            case 125: send(.breakAdjust(seconds: -60, now: CACurrentMediaTime())) // ↓
            default: break
            }
            return
        }
```
In `handleScroll(deltaY:modifiers:)` add a case:
```swift
        case .breakTimer:
            send(.breakAdjust(seconds: deltaY > 0 ? 60 : -60, now: CACurrentMediaTime()))
```

Image background: in `perform(.showOverlays)`'s implementation (`showOverlays()`), before creating controllers, load the break image when applicable:
```swift
        breakImage = nil
        if case .breakTimer = machine.state,
           case .imageFile(let path) = machine.settings.breakTimer.background,
           let nsImage = NSImage(contentsOfFile: path),
           let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            breakImage = cg
        }
```
and pass it to each controller next to the snapshot assignment:
```swift
            controller.breakImage = breakImage
```

Sound — add the effect case to `perform(_:)`:
```swift
        case .playExpirySound:
            if let sound = NSSound(named: "Glass") {
                sound.play()
            } else {
                NSSound.beep()
            }
```

- [ ] **Step 2: OverlayWindowController — breakImage passthrough**

```swift
    var breakImage: CGImage? {
        didSet { contentView.breakImage = breakImage }
    }
```

- [ ] **Step 3: OverlayContentView — break rendering**

Add property:
```swift
    var breakImage: CGImage? {
        didSet { needsDisplay = true }
    }
```

In `draw(_:)`, before the existing zoom-transform block, add an early branch:
```swift
        if case .breakTimer(let ctx) = state {
            drawBreak(ctx, in: cg)
            return
        }
```

Add rendering methods:
```swift
    private func drawBreak(_ ctx: BreakContext, in cg: CGContext) {
        let config = coordinator?.currentSettings().breakTimer ?? .default
        let bounds = CGRect(origin: .zero, size: screenFrame.size)

        // Background: black base, then faded snapshot or image when available.
        cg.setFillColor(.black)
        cg.fill(bounds)
        if case .fadedDesktop = config.background, let snapshot, !ctx.usedFallbackBackground {
            cg.interpolationQuality = .high
            cg.draw(snapshot, in: bounds)
            cg.setFillColor(CGColor(gray: 0, alpha: 0.7)) // fade
            cg.fill(bounds)
        } else if case .imageFile = config.background, let breakImage {
            cg.interpolationQuality = .high
            cg.draw(breakImage, in: aspectFillRect(for: breakImage, in: bounds))
        }

        // Timer text.
        let now = CACurrentMediaTime()
        let expired = ctx.timer.isExpired(at: now)
        let text: String
        let color: NSColor
        if expired {
            text = "-" + BreakTimer.format(ctx.timer.elapsedAfterExpiry(at: now))
            color = .systemRed
        } else {
            text = BreakTimer.format(ctx.timer.remaining(at: now))
            color = ctx.timer.isPaused ? .systemYellow : .white
        }
        let fontSize = screenFrame.height / 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color.withAlphaComponent(config.opacity),
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        string.draw(at: anchorOrigin(for: string.size(), position: config.position, in: bounds))
    }

    private func aspectFillRect(for image: CGImage, in bounds: CGRect) -> CGRect {
        let imageAspect = CGFloat(image.width) / CGFloat(image.height)
        let boundsAspect = bounds.width / bounds.height
        var size = bounds.size
        if imageAspect > boundsAspect {
            size.width = bounds.height * imageAspect
        } else {
            size.height = bounds.width / imageAspect
        }
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    private func anchorOrigin(for size: CGSize, position: BreakPosition, in bounds: CGRect) -> CGPoint {
        let margin = bounds.width * 0.05
        // Note: view coordinates are bottom-left origin, so "top" = maxY.
        let x: CGFloat = switch position {
        case .topLeft, .left, .bottomLeft: margin
        case .top, .center, .bottom: bounds.midX - size.width / 2
        case .topRight, .right, .bottomRight: bounds.maxX - margin - size.width
        }
        let y: CGFloat = switch position {
        case .bottomLeft, .bottom, .bottomRight: margin
        case .left, .center, .right: bounds.midY - size.height / 2
        case .topLeft, .top, .topRight: bounds.maxY - margin - size.height
        }
        return CGPoint(x: x, y: y)
    }
```

- [ ] **Step 4: Menu item + AppDelegate**

`StatusItemController.swift` — add `onBreak: @escaping () -> Void` to init (after onDraw), store it, add menu item after Draw:
```swift
        menu.addItem(makeItem("Break Timer", action: #selector(breakTapped), key: "3"))
```
and:
```swift
    @objc private func breakTapped() { onBreak() }
```

`AppDelegate.swift` — pass the callback:
```swift
        statusItemController = StatusItemController(
            onZoom: { coordinator.trigger(.toggleZoom) },
            onDraw: { coordinator.trigger(.toggleDraw) },
            onBreak: { coordinator.trigger(.toggleBreak) },
            onShortcuts: { shortcutsWindow.show() },
            onSettings: { settingsWindow.show() }
        )
```

- [ ] **Step 5: Build, regression suite, smoke**

Run: `xcodegen && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -1 && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

Manual smoke (human): ⌃3 → black screen with centered white countdown from 10:00; ↑/↓/scroll adjusts; Space pauses (yellow); Esc exits; let a 1-minute timer expire → Glass sound, red -0:01 counting up; menu bar → Break Timer also works.

- [ ] **Step 6: Commit**

```bash
git add ZoomIt4Mac
git commit -m "Add break timer shell: rendering, tick timer, input, sound, menu"
```

---

### Task 6: Settings UI + shortcuts panel + docs

**Files:**
- Modify: `ZoomIt4Mac/Sources/SettingsWindow.swift`, `ZoomIt4Mac/Sources/ShortcutsWindow.swift`, `README.md`

Shell task: build + regression + manual smoke.

- [ ] **Step 1: Settings — Break Timer section + hotkey row**

In `SettingsWindow.swift`, add a hotkey row in the Hotkeys section after Draw:
```swift
                hotkeyRow("Break Timer", action: .toggleBreak)
```

Add a new section after "Pen":
```swift
            Section("Break Timer") {
                LabeledContent("Duration") {
                    Stepper(
                        value: Binding(
                            get: { model.settings.breakTimer.duration / 60 },
                            set: { model.settings.breakTimer.duration = $0 * 60; model.save() }
                        ),
                        in: 1...99
                    ) {
                        Text("\(Int(model.settings.breakTimer.duration / 60)) min")
                            .monospacedDigit()
                            .fixedSize()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Picker("Position", selection: Binding(
                    get: { model.settings.breakTimer.position },
                    set: { model.settings.breakTimer.position = $0; model.save() }
                )) {
                    ForEach(BreakPosition.allCases, id: \.self) { position in
                        Text(positionLabel(position)).tag(position)
                    }
                }
                LabeledContent("Opacity") {
                    Slider(
                        value: Binding(
                            get: { model.settings.breakTimer.opacity },
                            set: { model.settings.breakTimer.opacity = $0; model.save() }
                        ),
                        in: 0.1...1.0
                    )
                    Text("\(Int(model.settings.breakTimer.opacity * 100)) %")
                        .monospacedDigit()
                        .fixedSize()
                        .frame(width: 44, alignment: .trailing)
                }
                Picker("Background", selection: Binding(
                    get: { backgroundKind(model.settings.breakTimer.background) },
                    set: { model.setBreakBackgroundKind($0) }
                )) {
                    Text("Solid black").tag(BackgroundKind.solid)
                    Text("Faded desktop").tag(BackgroundKind.desktop)
                    Text("Image…").tag(BackgroundKind.image)
                }
                if case .imageFile(let path) = model.settings.breakTimer.background {
                    LabeledContent("Image") {
                        Text((path as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { model.chooseBreakImage() }
                    }
                }
                Toggle("Show elapsed time after expiry", isOn: Binding(
                    get: { model.settings.breakTimer.showElapsedAfterExpiry },
                    set: { model.settings.breakTimer.showElapsedAfterExpiry = $0; model.save() }
                ))
                Toggle("Play sound on expiry", isOn: Binding(
                    get: { model.settings.breakTimer.playSound },
                    set: { model.settings.breakTimer.playSound = $0; model.save() }
                ))
            }
```

Supporting pieces (file scope + SettingsModel):
```swift
enum BackgroundKind: Hashable { case solid, desktop, image }

func backgroundKind(_ background: BreakBackground) -> BackgroundKind {
    switch background {
    case .solidBlack: .solid
    case .fadedDesktop: .desktop
    case .imageFile: .image
    }
}

func positionLabel(_ position: BreakPosition) -> String {
    switch position {
    case .topLeft: "Top left"
    case .top: "Top"
    case .topRight: "Top right"
    case .left: "Left"
    case .center: "Center"
    case .right: "Right"
    case .bottomLeft: "Bottom left"
    case .bottom: "Bottom"
    case .bottomRight: "Bottom right"
    }
}
```
On `SettingsModel`:
```swift
    func setBreakBackgroundKind(_ kind: BackgroundKind) {
        switch kind {
        case .solid: settings.breakTimer.background = .solidBlack
        case .desktop: settings.breakTimer.background = .fadedDesktop
        case .image: chooseBreakImage()
        }
        save()
    }

    func chooseBreakImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            settings.breakTimer.background = .imageFile(url.path)
            save()
        }
    }
```
(`import UniformTypeIdentifiers` at top of file for the content types.)

- [ ] **Step 2: Shortcuts panel — break entries**

In `ShortcutsWindow.swift` `makeSections`, add to Global:
```swift
            Shortcut(keys: comboLabel(hotkeys.combo(for: .toggleBreak)), action: "Break Timer — full-screen countdown"),
```
and a new section before "While typing":
```swift
        ShortcutSection(title: "During a break", shortcuts: [
            Shortcut(keys: "Space", action: "Pause / resume"),
            Shortcut(keys: "↑ ↓ / Scroll", action: "Add / remove one minute"),
            Shortcut(keys: "Right click / Esc", action: "End the break"),
        ]),
```

- [ ] **Step 3: README — feature entry**

In `README.md` Features section, add after the Type bullet:
```markdown
- **Break Timer** (`⌃3`) — full-screen countdown for presentation breaks. `Space` pauses, `↑` `↓` or scroll adjusts by a minute, Esc ends. Configurable duration (1–99 min), position, opacity, and background (solid black, faded desktop, or an image); optional sound and elapsed-time display on expiry.
```

- [ ] **Step 4: Build, full suite, smoke**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -1 && xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3`
Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

Manual smoke (human): Settings shows Break Timer hotkey row + section; all controls persist across relaunch; rebinding ⌃3 works; faded desktop background shows dimmed frozen desktop (with permission) and falls back to black without; image background aspect-fills; shortcuts panel lists break entries.

- [ ] **Step 5: Commit**

```bash
git add ZoomIt4Mac README.md
git commit -m "Add break timer settings, shortcuts reference, and docs"
```
