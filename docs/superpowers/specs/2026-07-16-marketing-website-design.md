# ZoomIt4Mac Marketing Website — Design

Date: 2026-07-16
Status: Approved (brainstorming complete)
Host: https://zoomit4mac.corti.com (user's own web server, manual upload)

## Goal

Single-page static marketing site: what the app does, screenshot-led feature
tour, download paths (DMG, Homebrew, GitHub), zero build tooling.

## Decisions

| Topic | Decision |
|---|---|
| Tech | Hand-written `index.html` + `style.css` + `script.js`. No framework, no build step |
| Location | `site/` directory in the ZoomIt4Mac repo; deploy = copy contents to the web server |
| Download links | "Download .dmg" button resolved at page load via the GitHub releases API (`/repos/TechPreacher/ZoomIt4Mac/releases/latest`) to the newest `.dmg` asset — versioned filenames make hardcoded URLs stale. Static `href` fallback = the releases-latest page, so the button works without JS or if the API call fails/rate-limits. Version string next to the button filled in from the same response |
| Homebrew | `brew install TechPreacher/tap/zoomit4mac` in a copyable code box with a copy button (Clipboard API; button hidden without JS) |
| Theme | Light/dark via `prefers-color-scheme`; accent from the app icon's strawberry red |
| Responsive | Single column on narrow screens; feature grid 2-up on desktop. No horizontal scroll |
| Images | Existing `Design/screenshot_*.{png,jpeg}` (3024×1964 Retina) copied into `site/assets/`, recompressed to web weight (max width 1600px, JPEG/WebP ~80 quality — the PNGs are 5–6 MB); app icon from `Design/icon-1024.png` downscaled to 256px + favicon sizes |
| Analytics/tracking | None |

## Page structure (top to bottom)

1. **Hero** — app icon, "ZoomIt4Mac", tagline "The Sysinternals ZoomIt experience — native on your Mac", subline (zoom, draw, record, snip from the menu bar; free & open source, macOS 14+), primary "Download .dmg" button + version, secondary Homebrew box, GitHub link. Hero screenshot below: `screenshot_shapes` (draw mode with shapes/highlighter/blur).
2. **Feature grid** — six cards, each screenshot + hotkey badge + 1–2 sentences:
   - Zoom (`⌃1`) — `screenshot_zoomed`
   - Draw & annotate (`⌃2`) — `screenshot_shapes` (cropped variant ok to reuse)
   - Break Timer (`⌃3`) — `screenshot_break_timer`
   - Type (`T`) — `screenshot_text`
   - Snip (`⌃6`) — `screenshot_snip`
   - Everything in the menu bar — `screenshot_menu` (also covers Live Zoom ⌃4 + Recording ⌃5 in copy, no dedicated shots)
   Live Zoom and Screen Recording get text mention in the Draw/menu cards' copy plus a compact "also on board" bullet strip under the grid (Live Zoom ⌃4, Screen Recording ⌃5 with mic/system audio, rebindable hotkeys, shortcuts panel, launch at login).
3. **Install** — three tabs-free blocks side by side: DMG (drag to Applications), Homebrew (incl. one-time `brew trust techpreacher/tap` note), permissions note (Screen Recording required for Zoom/Live Zoom/Snip/Recording; mic optional).
4. **Footer** — GitHub repo link, MIT license, "ZoomIt and Sysinternals are trademarks of Microsoft Corporation; independent re-implementation, not affiliated" (mirrors README), © Sascha Corti.

## Files

```
site/
  index.html
  style.css
  script.js          # latest-release resolution + copy button (~30 lines)
  assets/
    icon-256.png  favicon-32.png  favicon-16.png  apple-touch-icon.png (180)
    hero-shapes.jpg  zoom.jpg  break-timer.jpg  text.jpg  snip.jpg  menu.jpg
```

`sips` handles all image resizing/recompression (no external tools). Open Graph + Twitter meta tags (title, description, hero image absolute URL on zoomit4mac.corti.com) for link previews.

## Error handling

- GitHub API unreachable/rate-limited: button keeps its static releases-page href; version text stays hidden.
- No JS: everything works except the copy button (hidden) and the direct-dmg resolution (falls back to releases page).

## Testing

No unit tests (static page). Verification: open `site/index.html` locally —
layout at 375px/768px/1440px widths, dark + light mode, button resolves to the
v1.0.0 dmg URL, copy button copies the brew command, all images load, HTML
passes a validator pass (tidy or W3C), Lighthouse-style sanity (images sized,
alt texts present). README gets a one-line deploy note.

## Out of scope

Blog/news, multi-page docs, analytics, newsletter, screenshot lightbox,
CI-driven deploy, Sparkle appcast hosting (revisit with auto-update feature).
