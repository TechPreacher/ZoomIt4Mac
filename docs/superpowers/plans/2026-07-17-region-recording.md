# Region Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ⌃⇧5 drag-selects a screen area (snip-style) and records exactly that region — existing codec/audio settings, recording notice, and a border frame that marks the bounds without appearing in the recording.

**Architecture:** Third `SnipKind` (`.record`) reuses the drag-select machinery; `RecordingPhase.pending` carries the selected region through the notice wait; `.startRecording` effect gains `region: CGRect?` (nil = full display); shell converts via new pure `RecordingGeometry` and feeds `SCStreamConfiguration.sourceRect`. Spec: `docs/superpowers/specs/2026-07-17-region-recording-design.md`.

**Tech Stack:** Swift 6, ScreenCaptureKit (`sourceRect`), AppKit shell, Swift Testing (core).

## Global Constraints

- ZoomItCore stays pure Swift (no AppKit/ScreenCaptureKit imports); no Date/Timer in core; headless tests with EXACT effect arrays.
- Default hotkey (exact): `KeyCombo(keyCode: 23, modifiers: [.control, .shift])` — ⌃⇧5. `[.control, .shift]` rawValue = 5 in persisted JSON.
- Minimum region for `.record`: **32 pt per edge** (`SnipGeometry.minimumRecordingEdge`); image/text kinds keep 4 pt. Sub-minimum drag retries with kind preserved.
- Release effects for `.record` (exact order): `[.dismissOverlays, .showRecordingNotice]` — no snapshot read, notice must not sit under overlays.
- Full-display ⌃5 behavior byte-identical apart from mechanical payload additions: `.pending(region: nil)` / `.startRecording(region: nil)`.
- Output pixel dimensions rounded DOWN to even (hardware encoder requirement), floor 2×2.
- Frame window: `sharingType = .none` (never captured), click-through, non-activating.
- Branch: `feature/region-recording` (stacked on `feature/ocr-snip` — `SnipKind` exists).
- Build: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build`
- Tests: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`
- Test suites are per-scenario structs (e.g. `SessionRecordingTests`, `SnipSessionTests`) — use those names with `-only-testing:`, not `SessionStateMachineTests`.
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Core — `HotkeyAction.regionRecord` + default ⌃⇧5

**Files:**
- Modify: `ZoomItCore/Sources/HotkeyConfiguration.swift` (enum ~line 34, defaults ~line 41)
- Test: `ZoomItCore/Tests/HotkeyConfigurationTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `HotkeyAction.regionRecord` (rawValue `"regionRecord"`); default `KeyCombo(keyCode: 23, modifiers: [.control, .shift])`.

- [ ] **Step 1: Write the failing tests**

Append inside the test struct in `ZoomItCore/Tests/HotkeyConfigurationTests.swift` (templates: `ocrSnipDefaultIsCtrlOption6`, `persistedJSONWithoutOcrSnipFallsBackToCtrlOption6`):

```swift
    @Test func regionRecordDefaultIsCtrlShift5() {
        #expect(HotkeyConfiguration.default.combo(for: .regionRecord) == KeyCombo(keyCode: 23, modifiers: [.control, .shift]))
        #expect(HotkeyConfiguration.default.conflictingCombos().isEmpty)
    }

    // Migration: hotkey JSON persisted before regionRecord existed has no
    // regionRecord key — combo(for:) must fall back to ⌃⇧5. Pinned.
    @Test func persistedJSONWithoutRegionRecordFallsBackToCtrlShift5() throws {
        let json = #"{"bindings":{"toggleRecord":{"keyCode":23,"modifiers":1}}}"#
        let config = try JSONDecoder().decode(HotkeyConfiguration.self, from: Data(json.utf8))
        #expect(config.combo(for: .toggleRecord) == KeyCombo(keyCode: 23, modifiers: .control))
        #expect(config.combo(for: .regionRecord) == KeyCombo(keyCode: 23, modifiers: [.control, .shift]))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/HotkeyConfigurationTests
```
Expected: BUILD FAILS — no member `regionRecord`.

- [ ] **Step 3: Implement**

Enum becomes:

```swift
public enum HotkeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case toggleZoom, toggleDraw, toggleBreak, toggleLiveZoom, toggleRecord, snip, ocrSnip, regionRecord
}
```

Default bindings gain (after `.ocrSnip`):

```swift
        .regionRecord: KeyCombo(keyCode: 23, modifiers: [.control, .shift]), // ⌃⇧5
```

- [ ] **Step 4: Run tests to verify they pass**

Same command. Expected: all PASS.

- [ ] **Step 5: Commit**

```sh
git add ZoomItCore/Sources/HotkeyConfiguration.swift ZoomItCore/Tests/HotkeyConfigurationTests.swift
git commit -m "Add regionRecord hotkey action with ⌃⇧5 default

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Core — `RecordingGeometry` + kind-aware minimum edge

**Files:**
- Create: `ZoomItCore/Sources/RecordingGeometry.swift`
- Modify: `ZoomItCore/Sources/SnipGeometry.swift:8,20-25`
- Test: create `ZoomItCore/Tests/RecordingGeometryTests.swift`; extend `ZoomItCore/Tests/SnipGeometryTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `RecordingGeometry.sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect?`; `RecordingGeometry.outputPixelSize(sourceRect: CGRect, scale: CGFloat) -> CGSize`; `SnipGeometry.minimumRecordingEdge: CGFloat` (= 32); `SnipGeometry.isValidSelection(_ rect: CGRect, minimumEdge: CGFloat = SnipGeometry.minimumSelectionEdge) -> Bool` (default keeps every existing call site compiling).

- [ ] **Step 1: Write the failing tests**

Create `ZoomItCore/Tests/RecordingGeometryTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import ZoomItCore

struct RecordingGeometryTests {
    // Display 1000×600 at global origin (0,0); AppKit bottom-left origin.
    let display = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test func convertsToTopLeftDisplayRelative() {
        // Selection 100pt from left, top edge 150pt below display top.
        let selection = CGRect(x: 100, y: 250, width: 300, height: 200)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display)
        #expect(rect == CGRect(x: 100, y: 150, width: 300, height: 200))
    }

    @Test func clampsToDisplay() {
        let selection = CGRect(x: -50, y: -50, width: 200, height: 200)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display)
        #expect(rect == CGRect(x: 0, y: 450, width: 150, height: 150))
    }

    @Test func negativeOriginDisplay() {
        let display2 = CGRect(x: -1000, y: -600, width: 1000, height: 600)
        let selection = CGRect(x: -900, y: -500, width: 100, height: 100)
        let rect = RecordingGeometry.sourceRect(selection: selection, displayFrame: display2)
        #expect(rect == CGRect(x: 100, y: 200, width: 100, height: 100))
    }

    @Test func offDisplaySelectionIsNil() {
        let selection = CGRect(x: 2000, y: 2000, width: 100, height: 100)
        #expect(RecordingGeometry.sourceRect(selection: selection, displayFrame: display) == nil)
    }

    @Test func nanInputsAreNil() {
        let selection = CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100)
        #expect(RecordingGeometry.sourceRect(selection: selection, displayFrame: display) == nil)
    }

    @Test func outputSizeRoundsDownToEven() {
        // 101.5pt × 2× = 203px → 202; 100pt × 2× = 200 stays.
        let size = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 101.5, height: 100), scale: 2)
        #expect(size == CGSize(width: 202, height: 200))
    }

    @Test func outputSizeFloorsAtTwo() {
        let size = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 0.4, height: 0.4), scale: 1)
        #expect(size == CGSize(width: 2, height: 2))
        let degenerate = RecordingGeometry.outputPixelSize(sourceRect: CGRect(x: 0, y: 0, width: 100, height: 100), scale: -1)
        #expect(degenerate == CGSize(width: 2, height: 2))
    }
}
```

Append to the test struct in `ZoomItCore/Tests/SnipGeometryTests.swift`:

```swift
    @Test func recordingMinimumEdgeIsStricter() {
        let small = CGRect(x: 0, y: 0, width: 31, height: 31)
        let ok = CGRect(x: 0, y: 0, width: 32, height: 32)
        #expect(SnipGeometry.isValidSelection(small)) // 4pt default still passes
        #expect(!SnipGeometry.isValidSelection(small, minimumEdge: SnipGeometry.minimumRecordingEdge))
        #expect(SnipGeometry.isValidSelection(ok, minimumEdge: SnipGeometry.minimumRecordingEdge))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/RecordingGeometryTests -only-testing:ZoomItCoreTests/SnipGeometryTests
```
Expected: BUILD FAILS — `RecordingGeometry` not found, no `minimumRecordingEdge`.

- [ ] **Step 3: Implement**

Create `ZoomItCore/Sources/RecordingGeometry.swift`:

```swift
import CoreGraphics

/// Pure geometry for region recording: global-selection → ScreenCaptureKit
/// sourceRect conversion, and even-pixel output sizing.
public enum RecordingGeometry {
    /// Selection (global bottom-left-origin points) → SCStreamConfiguration
    /// sourceRect (display-relative points, top-left origin), clamped to the
    /// display. Nil when any input is degenerate or the clamped rect is
    /// under a point on either edge.
    public static func sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect? {
        guard selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite,
              displayFrame.origin.x.isFinite, displayFrame.origin.y.isFinite,
              displayFrame.width.isFinite, displayFrame.height.isFinite
        else { return nil }
        let clamped = selection.intersection(displayFrame)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return CGRect(
            x: clamped.minX - displayFrame.minX,
            y: displayFrame.maxY - clamped.maxY,
            width: clamped.width,
            height: clamped.height
        )
    }

    /// Output size in pixels, rounded down to even values (hardware encoders
    /// require even dimensions), floored at 2×2.
    public static func outputPixelSize(sourceRect: CGRect, scale: CGFloat) -> CGSize {
        guard scale.isFinite, scale > 0,
              sourceRect.width.isFinite, sourceRect.height.isFinite
        else { return CGSize(width: 2, height: 2) }
        let width = max(2, Int(sourceRect.width * scale) & ~1)
        let height = max(2, Int(sourceRect.height * scale) & ~1)
        return CGSize(width: width, height: height)
    }
}
```

In `ZoomItCore/Sources/SnipGeometry.swift`, add after `minimumSelectionEdge` (line 8):

```swift
    /// Recording needs a substantially larger region than a snip — tiny
    /// regions produce degenerate encoder dimensions.
    public static let minimumRecordingEdge: CGFloat = 32
```

and change `isValidSelection` to:

```swift
    public static func isValidSelection(_ rect: CGRect, minimumEdge: CGFloat = SnipGeometry.minimumSelectionEdge) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width >= minimumEdge
            && rect.height >= minimumEdge
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: all PASS.

- [ ] **Step 5: Commit** (new file needs no xcodegen for tests? It does — new files require regen. Run `xcodegen` before the test run in Step 2/4 — the commands above assume the project already includes the new files; if Step 2's build cannot find the test file, run `xcodegen` first.)

```sh
xcodegen
git add ZoomItCore/Sources/RecordingGeometry.swift ZoomItCore/Tests/RecordingGeometryTests.swift ZoomItCore/Sources/SnipGeometry.swift ZoomItCore/Tests/SnipGeometryTests.swift
git commit -m "Add recording geometry and kind-aware minimum selection edge

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Core — region-aware recording phase and snip kind `.record`

**Files:**
- Modify: `ZoomItCore/Sources/SessionStateMachine.swift` (RecordingPhase ~line 138-145, SnipKind ~line 51, CaptureTarget ~line 32, SessionEffect `.startRecording` ~line 122, `handle` top-level ~lines 165-201, idle handler, handleCapturing, handleSnip ~lines 305-341)
- Test: `ZoomItCore/Tests/SessionStateMachineTests.swift` (SessionRecordingTests ~line 693+, SnipSessionTests)

**Interfaces:**
- Consumes: `HotkeyAction.regionRecord` (Task 1), `SnipGeometry.minimumRecordingEdge` / `isValidSelection(_:minimumEdge:)` (Task 2).
- Produces: `RecordingPhase.pending(region: CGRect?)`; `SessionEffect.startRecording(region: CGRect?)`; `SnipKind.record`; `CaptureTarget.regionRecord`.

- [ ] **Step 1: Update existing tests mechanically and add the new ones**

Mechanical updates in `SessionRecordingTests` (and anywhere else these patterns appear — grep the test file):
- `m.recordingPhase == .pending` → `m.recordingPhase == .pending(region: nil)`
- effect `.startRecording` → `.startRecording(region: nil)`

New tests appended to the test file, in the existing suites' style (`machine()`, `testMouse`, `testScreen` helpers; add a `regionSelectionMachine()` helper mirroring `recordingMachine()`):

```swift
/// ⌃⇧5 through capture into .record snip selection.
func regionSelectionMachine(_ base: SessionStateMachine = machine()) -> SessionStateMachine {
    var m = base
    m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
    m.handle(.captureCompleted)
    return m
}

struct RegionRecordingTests {
    @Test func regionHotkeyStartsSelectionCapture() {
        var m = machine()
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.captureScreens])
        #expect(m.state == .capturing(.regionRecord))
        #expect(m.recordingPhase == .off)
    }

    @Test func captureCompletedEntersRecordSnip() {
        var m = machine()
        m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureCompleted) == [.showOverlays, .render])
        #expect(m.state == .snip(SnipContext(kind: .record)))
    }

    @Test func releaseShowsNoticeCarryingRegion() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        let fx = m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        #expect(fx == [.dismissOverlays, .showRecordingNotice])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .pending(region: CGRect(x: 100, y: 100, width: 200, height: 150)))
        #expect(!m.isRecording)
    }

    @Test func noticeElapsedStartsRegionRecording() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        let fx = m.handle(.recordingNoticeElapsed)
        #expect(fx == [.dismissRecordingNotice, .startRecording(region: CGRect(x: 100, y: 100, width: 200, height: 150))])
        #expect(m.isRecording)
    }

    @Test func regionHotkeyDuringNoticeCancels() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.dismissRecordingNotice])
        #expect(m.recordingPhase == .off)
        #expect(m.handle(.recordingNoticeElapsed).isEmpty)
    }

    @Test func regionHotkeyWhileActiveStops() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        m.handle(.recordingNoticeElapsed)
        #expect(m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(m.recordingPhase == .off)
    }

    @Test func toggleRecordStopsRegionRecording() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        m.handle(.leftMouseUp(CGPoint(x: 300, y: 250), optionHeld: false))
        m.handle(.recordingNoticeElapsed)
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.stopRecording])
        #expect(!m.isRecording)
    }

    @Test func subMinimumDragRetriesPreservingRecordKind() {
        var m = regionSelectionMachine()
        m.handle(.leftMouseDown(CGPoint(x: 100, y: 100)))
        // 31pt: over the 4pt snip minimum, under the 32pt recording minimum.
        let fx = m.handle(.leftMouseUp(CGPoint(x: 131, y: 131), optionHeld: false))
        #expect(fx == [.render])
        #expect(m.state == .snip(SnipContext(kind: .record)))
        #expect(m.recordingPhase == .off)
    }

    @Test func escapeDuringSelectionCancelsCleanly() {
        var m = regionSelectionMachine()
        #expect(m.handle(.escape) == [.dismissOverlays])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .off)
    }

    @Test func fullDisplayRecordingStillCarriesNilRegion() {
        var m = machine()
        #expect(m.handle(.hotkey(.toggleRecord, mouse: testMouse, screen: testScreen)) == [.showRecordingNotice])
        #expect(m.recordingPhase == .pending(region: nil))
        #expect(m.handle(.recordingNoticeElapsed) == [.dismissRecordingNotice, .startRecording(region: nil)])
    }

    @Test func regionCaptureFailureRoutesLikeSnip() {
        var m = machine()
        m.handle(.hotkey(.regionRecord, mouse: testMouse, screen: testScreen))
        #expect(m.handle(.captureFailed(.permissionDenied)) == [.showPermissionGuidance])
        #expect(m.state == .idle)
        #expect(m.recordingPhase == .off)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: BUILD FAILS — `.pending(region:)`, `.startRecording(region:)`, `.record`, `.regionRecord` unknown.

- [ ] **Step 3: Implement**

In `ZoomItCore/Sources/SessionStateMachine.swift`:

`RecordingPhase` (lines ~138-145):

```swift
public enum RecordingPhase: Equatable, Sendable {
    case off
    /// The "recording is starting" notice is showing; capture hasn't begun.
    /// region: selected area in global screen points; nil = full display.
    case pending(region: CGRect?)
    /// Capture is running.
    case active
}
```

(Keep the enum's existing access level and conformances if they differ — the payload is the only change.)

`SnipKind`:

```swift
public enum SnipKind: Equatable, Sendable {
    case image, text, record
}
```

`CaptureTarget` — add `case regionRecord`.

`SessionEffect` — `.startRecording` becomes:

```swift
    case startRecording(region: CGRect?)
```

Top-level `handle` — `.toggleRecord` case: `.off` branch becomes `recordingPhase = .pending(region: nil)` (effects unchanged). Add immediately after the `.toggleRecord` case:

```swift
        case .hotkey(.regionRecord, _, _) where recordingPhase != .off:
            if case .active = recordingPhase {
                recordingPhase = .off
                return [.stopRecording]
            }
            recordingPhase = .off
            return [.dismissRecordingNotice]
```

(The `where` guard lets an `.off`-phase ⌃⇧5 fall through to the per-state handlers below — idle starts selection; active modes exit via their generic `.hotkey` handling, same as snip.)

`.recordingNoticeElapsed` becomes:

```swift
        case .recordingNoticeElapsed:
            guard case .pending(let region) = recordingPhase else { return [] }
            recordingPhase = .active
            return [.dismissRecordingNotice, .startRecording(region: region)]
```

Idle handler — after the `.hotkey(.ocrSnip, _, _)` case:

```swift
        case .hotkey(.regionRecord, _, _):
            state = .capturing(.regionRecord)
            return [.captureScreens]
```

`handleCapturing` — after the `.ocrSnip` cases:

```swift
        case (.captureCompleted, .regionRecord):
            state = .snip(SnipContext(kind: .record))
            return [.showOverlays, .render]
        case (.captureFailed(.permissionDenied), .regionRecord):
            state = .idle
            return [.showPermissionGuidance]
        case (.captureFailed(.captureError), .regionRecord):
            state = .idle
            return [.notifyCaptureFailure]
```

`handleSnip` `leftMouseUp` — replace the validity guard and kind switch:

```swift
        case .leftMouseUp(let point, let optionHeld):
            guard let anchor = ctx.anchor else { return [] }
            let selection = SnipGeometry.normalized(anchor: anchor, current: point)
            let minimumEdge = ctx.kind == .record
                ? SnipGeometry.minimumRecordingEdge
                : SnipGeometry.minimumSelectionEdge
            guard SnipGeometry.isValidSelection(selection, minimumEdge: minimumEdge) else {
                // Stray click / sub-minimum drag: clear and let the user retry.
                state = .snip(SnipContext(kind: ctx.kind))
                return [.render]
            }
            state = .idle
            switch ctx.kind {
            case .image:
                // Export first — dismissOverlays clears the snapshot store the
                // crop reads from.
                return [.exportSnip(selection: selection, alsoSave: optionHeld), .dismissOverlays]
            case .text:
                // optionHeld deliberately ignored: no save-to-file variant for text.
                return [.recognizeText(selection: selection), .dismissOverlays]
            case .record:
                // No snapshot read — overlays go first so the notice never
                // sits under them. optionHeld deliberately ignored.
                recordingPhase = .pending(region: selection)
                return [.dismissOverlays, .showRecordingNotice]
            }
```

The shell will not compile against `.startRecording(region:)` yet — update `SessionCoordinator.perform`'s case to a temporary binding stub if needed:

```swift
        case .startRecording(region: _):
            startRecording()
```

(Task 5 replaces this; note in your report if added.)

- [ ] **Step 4: Run the full suite to verify all pass**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: all PASS — new `RegionRecordingTests` plus every pre-existing recording/snip test (with the mechanical payload updates).

- [ ] **Step 5: Commit**

```sh
git add ZoomItCore/Sources/SessionStateMachine.swift ZoomItCore/Tests/SessionStateMachineTests.swift ZoomIt4Mac/Sources/SessionCoordinator.swift
git commit -m "Add record snip kind with region-carrying recording phase

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Include `SessionCoordinator.swift` only if the stub was needed.)

---

### Task 4: Shell — `RecordingFrameWindow` + region-aware recorder

**Files:**
- Create: `ZoomIt4Mac/Sources/RecordingFrameWindow.swift`
- Modify: `ZoomIt4Mac/Sources/ScreenRecorderController.swift` (protocol lines 8-14, start ~lines 26-32, config block ~lines 66-79)

**Interfaces:**
- Consumes: `RecordingGeometry.outputPixelSize(sourceRect:scale:)` (Task 2).
- Produces: `RecordingFrameController` (`@MainActor`) with `show(around rect: CGRect)` / `dismiss()`; `ScreenRecording.start(displayID:codec:region:microphone:systemAudio:onError:)` — `region: CGRect?` in SCK sourceRect space (display-relative, top-left origin), nil = full display.

- [ ] **Step 1: Create `ZoomIt4Mac/Sources/RecordingFrameWindow.swift`**

```swift
import AppKit

/// Thin border marking the recorded region for the duration of a region
/// recording. sharingType == .none keeps the window out of every capture,
/// so the frame itself is never part of the recording.
@MainActor
final class RecordingFrameController {
    private var window: NSWindow?

    /// rect: recorded bounds in global screen points (bottom-left origin).
    func show(around rect: CGRect) {
        dismiss()
        // Stroke sits just outside the recorded bounds so no content is covered.
        let frameRect = rect.insetBy(dx: -3, dy: -3)
        let window = NSWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentView = RecordingFrameView(frame: NSRect(origin: .zero, size: frameRect.size))
        window.orderFrontRegardless()
        self.window = window
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class RecordingFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}
```

- [ ] **Step 2: Thread the region through the recorder**

In `ZoomIt4Mac/Sources/ScreenRecorderController.swift`:

Protocol:

```swift
@MainActor
protocol ScreenRecording: AnyObject {
    func start(
        displayID: CGDirectDisplayID,
        codec: RecordingCodec,
        region: CGRect?,
        microphone: Bool,
        systemAudio: Bool,
        onError: @escaping @MainActor (CaptureFailure) -> Void
    )
    func stop(completion: @escaping @MainActor (URL?) -> Void)
}
```

`start` gains `region: CGRect?,` after `codec`. The pixel-size/config block becomes:

```swift
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                let scale = self.scaleFactor(for: displayID)
                let pixelSize: CGSize
                if let region {
                    // region is already in SCK sourceRect space (display-
                    // relative points, top-left origin), clamped by the
                    // coordinator via RecordingGeometry.
                    config.sourceRect = region
                    pixelSize = RecordingGeometry.outputPixelSize(sourceRect: region, scale: scale)
                } else {
                    pixelSize = CGSize(
                        width: CGFloat(display.width) * scale,
                        height: CGFloat(display.height) * scale
                    )
                }
                config.width = Int(pixelSize.width)
                config.height = Int(pixelSize.height)
                config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                config.queueDepth = 6
                config.showsCursor = true
                config.capturesAudio = systemAudio
                config.pixelFormat = kCVPixelFormatType_32BGRA
```

(`RecordingWriter` construction is unchanged — it already takes `videoSize: pixelSize`, so the bitrate scales to the region automatically.)

If the file does not already import ZoomItCore, add `import ZoomItCore` (it does — verify).

- [ ] **Step 3: Temporarily satisfy the coordinator**

`SessionCoordinator.beginRecording`'s `recorder.start` call now needs the region argument. If Task 5 hasn't run yet, pass `region: nil` there so the build stays green, and note it in your report (Task 5 finishes the wiring):

```swift
        recorder.start(
            displayID: displayID,
            codec: recording.codec,
            region: nil,
            microphone: recording.recordMicrophone,
            systemAudio: recording.recordSystemAudio,
            onError: { [weak self] _ in
                self?.send(.recordingFailed)
            }
        )
```

- [ ] **Step 4: Regenerate (new file), build**

Run:
```sh
xcodegen
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED, no new warnings.

- [ ] **Step 5: Commit**

```sh
git add ZoomIt4Mac/Sources/RecordingFrameWindow.swift ZoomIt4Mac/Sources/ScreenRecorderController.swift ZoomIt4Mac/Sources/SessionCoordinator.swift
git commit -m "Add recording frame window and region-aware recorder

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Shell — coordinator region wiring

**Files:**
- Modify: `ZoomIt4Mac/Sources/SessionCoordinator.swift` (effect switch `.startRecording`/`.stopRecording` ~lines 335-353, `showRecordingNotice` ~line 356, `startRecording` ~line 378, `beginRecording` ~line 428)

**Interfaces:**
- Consumes: `.startRecording(region:)` (Task 3); `RecordingFrameController`, region-aware `recorder.start` (Task 4); `RecordingGeometry.sourceRect` (Task 2); existing `overlapArea(_:_:)` helper.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Frame controller property**

Near the coordinator's other owned controllers (next to `recordingNotice`):

```swift
    private let recordingFrame = RecordingFrameController()
```

- [ ] **Step 2: Effect wiring**

`.startRecording` case becomes (replacing any Task-3 stub):

```swift
        case .startRecording(let region):
            startRecording(region: region)
```

`.stopRecording` case — add frame dismissal as the first line inside the case:

```swift
        case .stopRecording:
            recordingFrame.dismiss()
            recorder.stop { [weak self] url in
                guard let self, let url else { return }
                // Reveal now if idle, else defer until the session settles
                // (see pendingRevealURL) so Finder activation doesn't steal
                // keyboard focus from an active overlay mode.
                if self.machine.state == .idle {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    self.pendingRevealURL = url
                }
            }
```

- [ ] **Step 3: Notice shows the right stop combo**

In `showRecordingNotice()`, the combo line becomes:

```swift
        let stopAction: HotkeyAction = if case .pending(let region) = machine.recordingPhase, region != nil {
            .regionRecord
        } else {
            .toggleRecord
        }
        let combo = comboLabel(machine.settings.hotkeys.combo(for: stopAction))
```

- [ ] **Step 4: Region-aware `startRecording`**

Signature becomes `private func startRecording(region: CGRect?)`. The display/geometry section (after the permission guard, replacing the mouse-screen lines) becomes:

```swift
        let screen: NSScreen?
        var sourceRect: CGRect?
        if let region {
            screen = NSScreen.screens.max { a, b in
                overlapArea(region, a.frame) < overlapArea(region, b.frame)
            }
            guard let target = screen,
                  let converted = RecordingGeometry.sourceRect(selection: region, displayFrame: target.frame)
            else {
                NSSound.beep()
                send(.recordingFailed)
                return
            }
            sourceRect = converted
            // Frame marks the recorded bounds (clamped to the display);
            // sharingType == .none keeps it out of the recording.
            recordingFrame.show(around: region.intersection(target.frame))
        } else {
            screen = NSScreen.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
            sourceRect = nil
        }
        guard let screen else {
            send(.recordingFailed)
            return
        }
        let recording = machine.settings.recording
        let displayID = screen.displayID
```

Both `beginRecording` call sites in this function pass the rect through — `beginRecording(displayID: displayID, region: sourceRect, recording: recording)`.

Also: in the `.recordingFailed` path the frame must vanish — `beginRecording`'s `onError` closure gains `self?.recordingFrame.dismiss()` before `send(.recordingFailed)`, and the geometry-failure branch above never shows the frame before failing (order in the code: `recordingFrame.show` only after `converted` succeeds — the code above already guarantees this).

- [ ] **Step 5: `beginRecording` threads the region**

```swift
    private func beginRecording(displayID: CGDirectDisplayID, region: CGRect?, recording: RecordingConfiguration) {
        recorder.start(
            displayID: displayID,
            codec: recording.codec,
            region: region,
            microphone: recording.recordMicrophone,
            systemAudio: recording.recordSystemAudio,
            onError: { [weak self] _ in
                self?.recordingFrame.dismiss()
                self?.send(.recordingFailed)
            }
        )
    }
```

- [ ] **Step 6: Build + full suite**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 7: Commit**

```sh
git add ZoomIt4Mac/Sources/SessionCoordinator.swift
git commit -m "Wire region recording: display choice, frame, notice combo

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: UI surfaces — menu item, settings row, shortcuts row

**Files:**
- Modify: `ZoomIt4Mac/Sources/StatusItemController.swift`
- Modify: `ZoomIt4Mac/Sources/AppDelegate.swift`
- Modify: `ZoomIt4Mac/Sources/SettingsWindow.swift` (hotkey rows)
- Modify: `ZoomIt4Mac/Sources/ShortcutsWindow.swift` (Global + While-snipping rows)

**Interfaces:**
- Consumes: `HotkeyAction.regionRecord` (Task 1); existing `trigger(_:)`, `makeItem(_:action:key:modifiers:)`.
- Produces: `StatusItemController.init` gains `onRegionRecord: @escaping () -> Void` immediately after `onRecord`.

- [ ] **Step 1: StatusItemController**

Stored closure after `private let onRecord: () -> Void`:

```swift
    private let onRegionRecord: () -> Void
```

Init parameter after `onRecord: @escaping () -> Void,`:

```swift
        onRegionRecord: @escaping () -> Void,
```

(assign `self.onRegionRecord = onRegionRecord` with the others, before `super.init()`).

Menu construction — after the `recordItem` line and before Snip:

```swift
        menu.addItem(makeItem("Record Region", action: #selector(regionRecordTapped), key: "5", modifiers: [.control, .shift]))
```

Selector with the other handlers:

```swift
    @objc private func regionRecordTapped() { onRegionRecord() }
```

- [ ] **Step 2: AppDelegate wiring**

After `onRecord: { coordinator.trigger(.toggleRecord) },`:

```swift
            onRegionRecord: { coordinator.trigger(.regionRecord) },
```

- [ ] **Step 3: Settings hotkey row**

After `hotkeyRow("Recording", action: .toggleRecord)`:

```swift
                hotkeyRow("Record Region", action: .regionRecord)
```

- [ ] **Step 4: Shortcuts window**

Global section — after the Recording row:

```swift
            Shortcut(keys: comboLabel(hotkeys.combo(for: .regionRecord)), action: "Record Region — record a screen area"),
```

"While snipping" section — the release row becomes:

```swift
            Shortcut(keys: "Release", action: "Copy the region (Snip), copy its text (OCR Snip), or start recording (Record Region)"),
```

- [ ] **Step 5: Build**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED, no new warnings. (`HotkeyRegistrar.apply` iterates `HotkeyAction.allCases` — ⌃⇧5 auto-registers; no change there.)

- [ ] **Step 6: Commit**

```sh
git add ZoomIt4Mac/Sources/StatusItemController.swift ZoomIt4Mac/Sources/AppDelegate.swift ZoomIt4Mac/Sources/SettingsWindow.swift ZoomIt4Mac/Sources/ShortcutsWindow.swift
git commit -m "Add Record Region to menu, settings, and shortcuts reference

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Docs + full test run + interactive smoke

**Files:**
- Modify: `README.md` (Features list, Permissions section)
- Modify: `CLAUDE.md` (Implemented list)

- [ ] **Step 1: README feature bullet**

After the OCR Snip bullet:

```markdown
- **Record Region** (`⌃⇧5`) — like Snip, but records the selected area instead of the full display: same drag-select, then the usual recording notice and a thin red frame marking the recorded bounds (never part of the recording). Codec, microphone, and system-audio settings apply; press `⌃⇧5` (or `⌃5`) again to stop. Smaller region — smaller file.
```

README Permissions line: add Record Region to the Screen-Recording-permission list (replace "Zoom, Live Zoom, Snip, OCR Snip, and Screen Recording require" with "Zoom, Live Zoom, Snip, OCR Snip, Record Region, and Screen Recording require").

- [ ] **Step 2: CLAUDE.md implemented list**

After the Snip/OCR Snip entries, insert:

```
**Record Region** (⌃⇧5, drag-select area to record via SCStream sourceRect),
```

- [ ] **Step 3: Full suite**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: all PASS.

- [ ] **Step 4: Commit**

```sh
git add README.md CLAUDE.md
git commit -m "Document Record Region feature

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Interactive smoke (needs the user — TCC + display)**

Ask the user to run and report:

1. ⌃⇧5 → freeze + crosshair; drag ~800×600 over moving content; release → recording notice (shows ⌃⇧5 as stop combo) → red frame appears around region; recording runs.
2. ⌃⇧5 stops; file in `~/Movies/ZoomIt4Mac/` contains ONLY the region (frame not visible in the video), dimensions even and ≈ region × scale.
3. ⌃5 full-display recording unchanged (no frame, full screen file).
4. Start region recording, stop with ⌃5 — works (cross-toggle).
5. Drag < 32 pt → selection clears, still selecting; Esc cancels with no notice.
6. Region on secondary display (if available) records the right display.
7. Settings → rebind Record Region works; Shortcuts window lists ⌃⇧5; menu item "Record Region" triggers the flow.
8. HEVC/H.264 toggle + mic/system audio respected in region recordings.

- [ ] **Step 6: Record smoke results in the PR description**
