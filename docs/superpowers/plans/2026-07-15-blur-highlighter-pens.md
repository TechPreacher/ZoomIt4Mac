# Blur + Highlighter Pens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two new draw-mode pens — highlighter (`H`, translucent marker over any shape) and blur (`X`, Gaussian-blurred rectangle over the frozen snapshot, zoom-backed draw only).

**Architecture:** `Annotation` gains `indirect case highlighted(Annotation)` (wraps any geometric case; renderer applies 40 % alpha, ×3 width, multiply blend) and `.blurRect(CGRect)`. Pen style is canvas state (`PenStyle` on `AnnotationCanvas`, toggled via new `KeyCommand`s in `handleDraw`); `ShapeTracker` gains a `style:` parameter. The shell renders blur rects by cropping the frozen snapshot (reusing `SnipGeometry.pixelCrop`), applying `CIGaussianBlur`, and caching results per rect.

**Tech Stack:** Swift 6, ZoomItCore (pure Swift + CoreGraphics, Swift Testing), AppKit + CoreImage shell.

**Spec:** `docs/superpowers/specs/2026-07-15-blur-highlighter-pens-design.md`

## Global Constraints

- `ZoomItCore` must never import AppKit or CoreImage. No Date/Timer in core.
- Every core change ships with Swift Testing tests asserting **exact effect arrays** (order matters) and edge cases.
- No test may require TCC permissions or a display.
- Shell (`ZoomIt4Mac` target) has **no unit tests by design** — verified by build + interactive smoke.
- Only existing files are modified — do NOT run `xcodegen` (no files added/removed).
- Highlighter compositing: 40 % alpha, stroke width ×3, `.multiply` blend, round caps.
- Blur: `CIGaussianBlur` radius 12 image points (× backing scale in pixels), `clampedToExtent` before blurring.
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Build: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build`
- All tests: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`

---

### Task 1: Annotation model — `highlighted` wrapper and `blurRect`

**Files:**
- Modify: `ZoomItCore/Sources/Annotation.swift`
- Test: `ZoomItCore/Tests/AnnotationTests.swift`

**Interfaces:**
- Produces: `Annotation.highlighted(Annotation)` (indirect case), `Annotation.blurRect(CGRect)`, and `func scalingWidth(by factor: CGFloat) -> Annotation` (returns a copy with stroke/line/arrow/rectangle/ellipse width multiplied; `.text`, `.blurRect` unchanged; `.highlighted` scales its wrapped annotation). Tasks 3–4 rely on these exact names.

- [ ] **Step 1: Write the failing tests**

Append to `ZoomItCore/Tests/AnnotationTests.swift`:

```swift
struct AnnotationStyleTests {
    @Test func highlightedWrapsAnyGeometricCase() {
        let base = Annotation.line(from: .zero, to: CGPoint(x: 5, y: 5), color: .yellow, width: 4)
        let wrapped = Annotation.highlighted(base)
        #expect(wrapped == .highlighted(base))
        #expect(wrapped != base)
    }

    @Test func blurRectEquality() {
        let r = CGRect(x: 1, y: 2, width: 30, height: 40)
        #expect(Annotation.blurRect(r) == .blurRect(r))
        #expect(Annotation.blurRect(r) != .blurRect(r.insetBy(dx: 1, dy: 1)))
    }

    @Test func scalingWidthMultipliesStrokeCases() {
        let points = [CGPoint.zero, CGPoint(x: 10, y: 0)]
        #expect(Annotation.stroke(points: points, color: .red, width: 4).scalingWidth(by: 3)
            == .stroke(points: points, color: .red, width: 12))
        #expect(Annotation.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 2).scalingWidth(by: 3)
            == .line(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 6))
        #expect(Annotation.arrow(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 2).scalingWidth(by: 3)
            == .arrow(from: .zero, to: CGPoint(x: 1, y: 1), color: .blue, width: 6))
        let rect = CGRect(x: 0, y: 0, width: 5, height: 5)
        #expect(Annotation.rectangle(rect, color: .green, width: 1).scalingWidth(by: 3)
            == .rectangle(rect, color: .green, width: 3))
        #expect(Annotation.ellipse(in: rect, color: .green, width: 1).scalingWidth(by: 3)
            == .ellipse(in: rect, color: .green, width: 3))
    }

    @Test func scalingWidthLeavesTextAndBlurUntouched() {
        let text = Annotation.text("hi", at: .zero, color: .red, fontSize: 32)
        #expect(text.scalingWidth(by: 3) == text)
        let blur = Annotation.blurRect(CGRect(x: 0, y: 0, width: 5, height: 5))
        #expect(blur.scalingWidth(by: 3) == blur)
    }

    @Test func scalingWidthRecursesIntoHighlighted() {
        let base = Annotation.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .pink, width: 2)
        #expect(Annotation.highlighted(base).scalingWidth(by: 3)
            == .highlighted(.line(from: .zero, to: CGPoint(x: 1, y: 1), color: .pink, width: 6)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/AnnotationStyleTests 2>&1 | tail -15`
Expected: BUILD FAILS with `type 'Annotation' has no member 'highlighted'`

- [ ] **Step 3: Implement**

In `ZoomItCore/Sources/Annotation.swift`, change the enum declaration to add the two cases (after `.text`):

```swift
public enum Annotation: Equatable, Sendable {
    case stroke(points: [CGPoint], color: AnnotationColor, width: CGFloat)
    case line(from: CGPoint, to: CGPoint, color: AnnotationColor, width: CGFloat)
    case arrow(from: CGPoint, to: CGPoint, color: AnnotationColor, width: CGFloat)
    case rectangle(CGRect, color: AnnotationColor, width: CGFloat)
    case ellipse(in: CGRect, color: AnnotationColor, width: CGFloat)
    case text(String, at: CGPoint, color: AnnotationColor, fontSize: CGFloat)
    /// The wrapped annotation drawn as a highlighter stroke (translucent,
    /// wider, multiply-blended). Produced for every geometric shape.
    indirect case highlighted(Annotation)
    /// Region of the frozen snapshot rendered Gaussian-blurred (image space).
    case blurRect(CGRect)
```

Add the width-scaling helper inside the enum (after `arrowHead`):

```swift
    /// A copy with the stroke width of geometric cases multiplied; text and
    /// blur regions carry no stroke width and pass through unchanged.
    public func scalingWidth(by factor: CGFloat) -> Annotation {
        switch self {
        case let .stroke(points, color, width):
            .stroke(points: points, color: color, width: width * factor)
        case let .line(from, to, color, width):
            .line(from: from, to: to, color: color, width: width * factor)
        case let .arrow(from, to, color, width):
            .arrow(from: from, to: to, color: color, width: width * factor)
        case let .rectangle(rect, color, width):
            .rectangle(rect, color: color, width: width * factor)
        case let .ellipse(rect, color, width):
            .ellipse(in: rect, color: color, width: width * factor)
        case .text, .blurRect:
            self
        case let .highlighted(base):
            .highlighted(base.scalingWidth(by: factor))
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/AnnotationStyleTests 2>&1 | tail -15`
Expected: all AnnotationStyleTests PASS.

NOTE: the app target does NOT compile yet if `OverlayContentView.draw(_:in:)` switches exhaustively over `Annotation` — that switch gains its real cases in Task 4. Check: `xcodebuild ... build 2>&1 | tail -5`. If the build fails with "switch must be exhaustive" in OverlayContentView.swift, add a TEMPORARY placeholder to that switch and include it in this task's commit (Task 4 replaces it):

```swift
        case .highlighted, .blurRect:
            break // Rendering lands with the shell task.
        }
```

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore/Sources/Annotation.swift ZoomItCore/Tests/AnnotationTests.swift ZoomIt4Mac/Sources/OverlayContentView.swift
git commit -m "Add highlighted and blur-rect annotation cases

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Drop the OverlayContentView path from `git add` if no placeholder was needed.)

---

### Task 2: Pen style state and key commands in the state machine

**Files:**
- Modify: `ZoomItCore/Sources/AnnotationCanvas.swift`
- Modify: `ZoomItCore/Sources/SessionStateMachine.swift`
- Test: `ZoomItCore/Tests/SessionStateMachineTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1 (style state is independent of the new cases).
- Produces: `PenStyle` enum (`.normal`, `.highlighter`, `.blur`), `AnnotationCanvas.penStyle: PenStyle` (var, default `.normal`), `KeyCommand.toggleHighlighter` / `KeyCommand.toggleBlur`. Task 3's tracker takes a `PenStyle`; Task 4's coordinator reads `ctx.canvas.penStyle` and sends the new key commands.

- [ ] **Step 1: Write the failing tests**

Append to `ZoomItCore/Tests/SessionStateMachineTests.swift` as a new top-level suite:

```swift
struct PenStyleTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)

    /// Plain draw (no zoom context, no snapshot).
    private func plainDraw() -> SessionStateMachine {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleDraw, mouse: .zero, screen: screen))
        return m
    }

    /// Draw on a frozen zoom (zoom context present).
    private func zoomDraw() -> SessionStateMachine {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleZoom, mouse: CGPoint(x: 1, y: 1), screen: screen))
        m.handle(.captureCompleted)
        m.handle(.leftMouseDown(CGPoint(x: 1, y: 1)))
        return m
    }

    private func canvas(_ m: SessionStateMachine) -> AnnotationCanvas? {
        if case .draw(let ctx) = m.state { return ctx.canvas }
        return nil
    }

    @Test func defaultStyleIsNormal() {
        #expect(canvas(plainDraw())?.penStyle == .normal)
    }

    @Test func highlighterTogglesOnAndOff() {
        var m = plainDraw()
        #expect(m.handle(.keyCommand(.toggleHighlighter)) == [.render])
        #expect(canvas(m)?.penStyle == .highlighter)
        #expect(m.handle(.keyCommand(.toggleHighlighter)) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func blurTogglesInZoomBackedDraw() {
        var m = zoomDraw()
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .blur)
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func blurRefusedInPlainDraw() {
        var m = plainDraw()
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.notifyCaptureFailure])
        #expect(canvas(m)?.penStyle == .normal)
    }

    @Test func highlighterSwitchesDirectlyToBlur() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleHighlighter))
        m.handle(.keyCommand(.toggleBlur))
        #expect(canvas(m)?.penStyle == .blur)
    }

    @Test func colorKeyRevertsStyleToNormalAndSetsColor() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleBlur))
        #expect(m.handle(.keyCommand(.color(.green))) == [.render])
        #expect(canvas(m)?.penStyle == .normal)
        #expect(canvas(m)?.color == .green)
    }

    @Test func boardRevertsBlurButNotHighlighter() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleBlur))
        m.handle(.keyCommand(.whiteboard))
        #expect(canvas(m)?.penStyle == .normal)

        var h = zoomDraw()
        h.handle(.keyCommand(.toggleHighlighter))
        h.handle(.keyCommand(.blackboard))
        #expect(canvas(h)?.penStyle == .highlighter)
    }

    @Test func styleSurvivesTypeRoundTrip() {
        var m = zoomDraw()
        m.handle(.keyCommand(.toggleHighlighter))
        m.handle(.keyCommand(.enterType))
        m.handle(.escape)
        #expect(canvas(m)?.penStyle == .highlighter)
    }

    @Test func blurAllowedInDrawFromFrozenLiveZoom() {
        var m = SessionStateMachine(settings: .default)
        m.handle(.hotkey(.toggleLiveZoom, mouse: CGPoint(x: 1, y: 1), screen: screen))
        m.handle(.leftMouseDown(CGPoint(x: 1, y: 1)))
        m.handle(.liveFrameFrozen)
        #expect(m.handle(.keyCommand(.toggleBlur)) == [.render])
        #expect(canvas(m)?.penStyle == .blur)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/PenStyleTests 2>&1 | tail -15`
Expected: BUILD FAILS with `type 'KeyCommand' has no member 'toggleHighlighter'` (and missing `penStyle`).

- [ ] **Step 3: Implement**

**3a.** In `ZoomItCore/Sources/AnnotationCanvas.swift`, add above `AnnotationCanvas`:

```swift
public enum PenStyle: Equatable, Sendable {
    case normal, highlighter, blur
}
```

and inside `AnnotationCanvas` (next to `background`):

```swift
    public var penStyle: PenStyle = .normal
```

**3b.** In `ZoomItCore/Sources/SessionStateMachine.swift`, extend `KeyCommand`:

```swift
public enum KeyCommand: Equatable, Sendable {
    case color(AnnotationColor)
    case undo, eraseAll, whiteboard, blackboard, enterType
    case save, copy
    case fontIncrease, fontDecrease
    case toggleHighlighter, toggleBlur
}
```

**3c.** In `handleDraw`, replace the color case and the two board cases, and add the two toggles (before `case .penWidthChanged`):

```swift
        case .keyCommand(.color(let color)):
            ctx.canvas.color = color
            ctx.canvas.penStyle = .normal
```

```swift
        case .keyCommand(.whiteboard):
            ctx.canvas.background = ctx.canvas.background == .white ? .transparent : .white
            if ctx.canvas.penStyle == .blur { ctx.canvas.penStyle = .normal }
        case .keyCommand(.blackboard):
            ctx.canvas.background = ctx.canvas.background == .black ? .transparent : .black
            if ctx.canvas.penStyle == .blur { ctx.canvas.penStyle = .normal }
        case .keyCommand(.toggleHighlighter):
            ctx.canvas.penStyle = ctx.canvas.penStyle == .highlighter ? .normal : .highlighter
        case .keyCommand(.toggleBlur):
            // Blur needs a frozen snapshot behind the ink — zoom-backed draw only.
            guard ctx.zoom != nil else { return [.notifyCaptureFailure] }
            ctx.canvas.penStyle = ctx.canvas.penStyle == .blur ? .normal : .blur
```

(The shared `state = .draw(ctx); return [.render]` tail at the bottom of `handleDraw` handles the state write for all these cases.)

- [ ] **Step 4: Run the full core suite**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: ALL tests PASS (pre-existing draw tests must be undisturbed — the color/board cases only gain style writes).

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore/Sources/AnnotationCanvas.swift ZoomItCore/Sources/SessionStateMachine.swift ZoomItCore/Tests/SessionStateMachineTests.swift
git commit -m "Add pen style state with highlighter and blur toggles

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: ShapeTracker style support

**Files:**
- Modify: `ZoomItCore/Sources/ShapeTracker.swift`
- Test: `ZoomItCore/Tests/ShapeTrackerTests.swift`

**Interfaces:**
- Consumes: `PenStyle` (Task 2), `Annotation.highlighted` / `.blurRect` (Task 1).
- Produces: `ShapeTracker.init(shape:start:color:width:style:)` with `style: PenStyle = .normal` — Task 4's coordinator passes `ctx.canvas.penStyle`.

- [ ] **Step 1: Write the failing tests**

Append to `ZoomItCore/Tests/ShapeTrackerTests.swift`:

```swift
struct ShapeTrackerStyleTests {
    @Test func highlighterWrapsEveryShape() {
        let shapes: [ShapeKind] = [.freehand, .line, .arrow, .rectangle, .ellipse]
        for shape in shapes {
            var t = ShapeTracker(shape: shape, start: .zero, color: .yellow, width: 4, style: .highlighter)
            t.update(CGPoint(x: 20, y: 10))
            guard case .highlighted = t.finish() else {
                Issue.record("expected .highlighted for \(shape)")
                continue
            }
        }
    }

    @Test func highlighterPropagatesNilForEmptyDrags() {
        var freehand = ShapeTracker(shape: .freehand, start: .zero, color: .red, width: 4, style: .highlighter)
        #expect(freehand.finish() == nil) // single point, no movement
        var line = ShapeTracker(shape: .line, start: .zero, color: .red, width: 4, style: .highlighter)
        line.update(.zero)
        #expect(line.finish() == nil)
    }

    @Test func blurAlwaysYieldsNormalizedRect() {
        // Shape is ignored while the blur pen is active — always a rect.
        var t = ShapeTracker(shape: .arrow, start: CGPoint(x: 30, y: 40), color: .red, width: 4, style: .blur)
        t.update(CGPoint(x: 10, y: 20))
        #expect(t.finish() == .blurRect(CGRect(x: 10, y: 20, width: 20, height: 20)))
    }

    @Test func blurNilOnZeroDrag() {
        var t = ShapeTracker(shape: .freehand, start: CGPoint(x: 5, y: 5), color: .red, width: 4, style: .blur)
        t.update(CGPoint(x: 5, y: 5))
        #expect(t.finish() == nil)
    }

    @Test func defaultStyleKeepsExistingBehavior() {
        var t = ShapeTracker(shape: .line, start: .zero, color: .blue, width: 3)
        t.update(CGPoint(x: 4, y: 4))
        #expect(t.finish() == .line(from: .zero, to: CGPoint(x: 4, y: 4), color: .blue, width: 3))
    }

    @Test func previewMatchesFinishForStyles() {
        var t = ShapeTracker(shape: .rectangle, start: .zero, color: .green, width: 2, style: .highlighter)
        t.update(CGPoint(x: 8, y: 8))
        #expect(t.preview() == t.finish())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' -only-testing:ZoomItCoreTests/ShapeTrackerStyleTests 2>&1 | tail -15`
Expected: BUILD FAILS with `extra argument 'style' in call`.

- [ ] **Step 3: Implement**

In `ZoomItCore/Sources/ShapeTracker.swift`, add the stored property and init parameter, and route `finish()` through the style:

```swift
public struct ShapeTracker: Equatable, Sendable {
    public let shape: ShapeKind
    public let start: CGPoint
    public let color: AnnotationColor
    public let width: CGFloat
    public let style: PenStyle
    private var points: [CGPoint]
    private var current: CGPoint

    public init(shape: ShapeKind, start: CGPoint, color: AnnotationColor, width: CGFloat, style: PenStyle = .normal) {
        self.shape = shape
        self.start = start
        self.color = color
        self.width = width
        self.style = style
        self.points = [start]
        self.current = start
    }

    public mutating func update(_ point: CGPoint) {
        current = point
        if shape == .freehand { points.append(point) }
    }

    public func finish() -> Annotation? {
        if style == .blur {
            // Blur ignores the shape: always a normalized rectangle.
            guard current != start else { return nil }
            return .blurRect(normalizedRect)
        }
        guard let base = baseAnnotation() else { return nil }
        return style == .highlighter ? .highlighted(base) : base
    }

    public func preview() -> Annotation? { finish() }

    private func baseAnnotation() -> Annotation? {
        switch shape {
        case .freehand:
            guard points.count >= 2 else { return nil }
            return .stroke(points: points, color: color, width: width)
        case .line:
            guard current != start else { return nil }
            return .line(from: start, to: current, color: color, width: width)
        case .arrow:
            guard current != start else { return nil }
            return .arrow(from: start, to: current, color: color, width: width)
        case .rectangle:
            guard current != start else { return nil }
            return .rectangle(normalizedRect, color: color, width: width)
        case .ellipse:
            guard current != start else { return nil }
            return .ellipse(in: normalizedRect, color: color, width: width)
        }
    }

    private var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
```

(This replaces the previous `finish()` body — the per-shape logic moves verbatim into `baseAnnotation()`.)

- [ ] **Step 4: Run the full core suite**

Run: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -5`
Expected: ALL tests PASS (existing ShapeTrackerTests must pass unchanged — default style preserves behavior).

- [ ] **Step 5: Commit**

```bash
git add ZoomItCore/Sources/ShapeTracker.swift ZoomItCore/Tests/ShapeTrackerTests.swift
git commit -m "Route shape tracker output through pen style

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Shell — key routing, tracker style, highlighter and blur rendering, docs

**Files:**
- Modify: `ZoomIt4Mac/Sources/SessionCoordinator.swift`
- Modify: `ZoomIt4Mac/Sources/OverlayContentView.swift`
- Modify: `ZoomIt4Mac/Sources/ShortcutsWindow.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `KeyCommand.toggleHighlighter`/`.toggleBlur`, `ctx.canvas.penStyle` (Task 2), `ShapeTracker(style:)` (Task 3), `Annotation.highlighted`/`.blurRect` + `scalingWidth(by:)` (Task 1), `SnipGeometry.pixelCrop` (existing).
- Produces: nothing for later tasks (this is the last code task).

- [ ] **Step 1: Key routing**

In `ZoomIt4Mac/Sources/SessionCoordinator.swift`, in `handleKeyDown`'s draw block (the `switch chars` containing `case "e"`, `case "w"`…), add after `case "t"`:

```swift
            case "h": send(.keyCommand(.toggleHighlighter))
            case "x": send(.keyCommand(.toggleBlur))
```

- [ ] **Step 2: Tracker style**

In `handleMouseDown`, draw case — add the `style:` argument:

```swift
        case .draw(let ctx):
            activeTracker = ShapeTracker(
                shape: shapeKind(for: modifiers),
                start: imageSpacePoint(for: global),
                color: ctx.canvas.color,
                width: ctx.canvas.penWidth,
                style: ctx.canvas.penStyle
            )
```

- [ ] **Step 3: Rendering in OverlayContentView**

In `ZoomIt4Mac/Sources/OverlayContentView.swift`:

**3a.** Add `import CoreImage` after `import AppKit`.

**3b.** In `private func draw(_ annotation: Annotation, in cg: CGContext)`, replace the temporary placeholder from Task 1 (or add to the switch) with:

```swift
        case let .highlighted(base):
            cg.saveGState()
            cg.setAlpha(0.4)
            cg.setBlendMode(.multiply)
            draw(base.scalingWidth(by: 3), in: cg)
            cg.restoreGState()
        case let .blurRect(rect):
            drawBlurRect(rect, in: cg)
```

**3c.** Add the blur renderer and cache after `drawTypeRun`:

```swift
    // MARK: - Blur pen

    /// Blurred snapshot crops keyed by rect; cleared when the snapshot
    /// changes. Bounded so drag previews can't hoard memory.
    private let blurCache = NSCache<NSString, CGImage>()

    private func clearBlurCache() {
        blurCache.removeAllObjects()
        blurCache.countLimit = 64
    }

    /// Draw the frozen snapshot region Gaussian-blurred. `rect` is in image
    /// space (global points); the context is already translated so global
    /// coordinates draw at the right window-local spot.
    private func drawBlurRect(_ rect: CGRect, in cg: CGContext) {
        guard let snapshot else { return }
        let key = "\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)" as NSString
        if let cached = blurCache.object(forKey: key) {
            cg.interpolationQuality = .high
            cg.draw(cached, in: rect)
            return
        }
        let scale = CGFloat(snapshot.width) / screenFrame.width
        guard let pixelRect = SnipGeometry.pixelCrop(selection: rect, displayFrame: screenFrame, scale: scale),
              let crop = snapshot.cropping(to: pixelRect)
        else { return }
        let input = CIImage(cgImage: crop)
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: 12 * scale)
            .cropped(to: input.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let output = context.createCGImage(blurred, from: blurred.extent) else { return }
        blurCache.setObject(output, forKey: key)
        cg.interpolationQuality = .high
        cg.draw(output, in: rect)
    }
```

**3d.** Wire the cache clear into the snapshot property:

```swift
    var snapshot: CGImage? {
        didSet {
            clearBlurCache()
            needsDisplay = true
        }
    }
```

- [ ] **Step 4: Shortcuts panel + README**

`ZoomIt4Mac/Sources/ShortcutsWindow.swift`, "While drawing" section — add after the `W / K` row:

```swift
            Shortcut(keys: "H", action: "Highlighter pen (toggle)"),
            Shortcut(keys: "X", action: "Blur pen — drag a rectangle (frozen zoom only)"),
```

`README.md`, draw-mode table — add after the `W / K` row:

```markdown
  | `H` | highlighter pen (toggle) |
  | `X` | blur pen — drag a rectangle to blur (zoomed image only) |
```

- [ ] **Step 5: Build and run all tests**

```bash
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build 2>&1 | tail -3
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED, all tests PASS. If Task 1's placeholder is still in the annotation switch, it MUST be gone now (replaced by the real cases).

- [ ] **Step 6: Commit**

```bash
git add ZoomIt4Mac/Sources/SessionCoordinator.swift ZoomIt4Mac/Sources/OverlayContentView.swift ZoomIt4Mac/Sources/ShortcutsWindow.swift README.md
git commit -m "Render highlighter and blur pens in the overlay

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Interactive smoke pass (after all tasks)

1. ⌃1 zoom → click into draw → `H` → drag over text: translucent marker, text readable through it; all five shapes (plain, ⇧, ⌃, ⌃⇧, Tab) render translucent; color keys give a normal opaque pen again.
2. `X` in zoom-backed draw → drag rect over text: region blurred, unreadable; preview blurs live during the drag; undo (⌘Z) removes it; `E` erases all.
3. ⌃2 plain draw → `X` → beep, pen unchanged; `H` still works.
4. Live zoom ⌃4 → click (freeze) → `X` → blur works on the frozen frame.
5. `W` board while blur pen active → pen back to normal; highlighter survives boards.
6. ⌘S / ⌘C in a zoomed draw with blur + highlight → exported PNG/clipboard shows both baked in.
7. Retina display: blur region aligned exactly with the dragged rect (no offset/half-scale).
8. Pen width ⌘-scroll affects highlighter width (×3 of the shown width).
