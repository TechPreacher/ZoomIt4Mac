# Backlog

Open points carried out of the v1.1.0 release work (2026-07-17). None are
release-blocking; all came out of final code reviews or deferred operations.

## Code follow-ups (from final whole-branch reviews)

- [ ] **Guard the record-release phase assignment against a mid-selection ⌃5.**
  `SessionStateMachine.handleSnip`, `.record` release branch: sets
  `recordingPhase = .pending(region:)` unconditionally. Contrived sequence —
  ⌃⇧5 → (during region selection) ⌃5 → wait 2 s notice → full-display
  recording goes `.active` → then release the drag ≥32 pt → phase clobbered
  back to `.pending`; cancelling that notice orphans the live recording.
  Fix: only set `.pending` when `recordingPhase == .off` (or prepend
  `.stopRecording` when `.active`), plus a pinned effect-array test.

- [ ] **`handleDraw` swallows the snip-family hotkeys while actively drawing.**
  `handleDraw` has no generic `.hotkey` catch-all, so ⌃⌥6 (`.ocrSnip`) and
  ⌃⇧5 (`.regionRecord`) are silently ignored in draw mode, unlike `.snip`,
  which exits the mode. Pre-existing pattern; fix both actions together with
  a generic catch-all and state-machine tests.

- [ ] **Menu key-equivalents don't reflect rebinds.** Every status-menu item
  (`StatusItemController`) shows a hardcoded default combo (⌃1…⌃6, ⌃⌥6,
  ⌃⇧5) even after the user rebinds the action in Settings. Whole-menu fix:
  derive key equivalents from `settings.hotkeys` and refresh on
  `applySettings`. Cosmetic — actions themselves fire correctly. Related
  nit: the "Record Region" item title stays static while a region recording
  is active (clicking it stops correctly; label just doesn't say "Stop").

## Small hardening (nice-to-have, from task reviews)

- [ ] `scripts/release.sh`: early guards for empty `SPARKLE_BIN` / `VERSION`
  (currently fails late with an unclear error on a fresh machine) and a
  check that `CURRENT_PROJECT_VERSION` was bumped vs the committed
  `appcast.xml` (a forgotten bump makes a release invisible to Sparkle).
- [ ] `RecordingGeometry.sourceRect`: one-line doc comment stating the
  input contract (rects from `SnipGeometry.normalized`, non-negative
  extents).
- [ ] Notice-panel boilerplate duplicated between `RecordingNoticeWindow`
  and `SnipNoticeWindow` — factor a shared helper only if a third notice
  window appears.

## Pre-existing feature backlog

Catalogued with implementation notes in
`docs/superpowers/specs/2026-07-14-zoomit4mac-v1-design.md`: DemoType
(needs an Accessibility-permission rethink), right-aligned type, draw
niceties.
