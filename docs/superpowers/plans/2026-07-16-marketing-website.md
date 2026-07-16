# Marketing Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Single-page static marketing site for ZoomIt4Mac at https://zoomit4mac.corti.com — feature tour, download links, GitHub link.

**Architecture:** Three hand-written files (`site/index.html`, `site/style.css`, `site/script.js`) plus web-weight assets produced from `Design/` with `sips`. No framework, no build step. JS only enhances (latest-release URL resolution, copy button); static fallbacks everywhere.

**Tech Stack:** Plain HTML5/CSS3/vanilla JS. `sips` for image processing. Branch `feature/website`.

**Spec:** `docs/superpowers/specs/2026-07-16-marketing-website-design.md`

## Global Constraints

- No external resources on the page (no CDN fonts/scripts) — self-contained except the GitHub API call.
- Dark + light theme via `prefers-color-scheme`; accent = strawberry red `#d23c3c`.
- Every image has meaningful `alt` text; page has no horizontal scroll at 375 px.
- Download button static `href` = `https://github.com/TechPreacher/ZoomIt4Mac/releases/latest` (JS upgrades it to the direct `.dmg` URL).
- Trademark footer text mirrors README: independent re-implementation, not affiliated with Microsoft.
- Commit messages end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Branch + web assets

**Files:**
- Create: `site/assets/` (icon-256.png, apple-touch-icon.png, favicon-32.png, favicon-16.png, hero-shapes.jpg, zoom.jpg, break-timer.jpg, text.jpg, snip.jpg, menu.jpg)

**Interfaces:**
- Produces: the exact asset filenames above — Task 2's HTML references them verbatim.

- [ ] **Step 1: Create branch**

```bash
cd /Users/sascha/Temp/ZoomIt4Mac
git checkout main && git pull && git checkout -b feature/website
```

- [ ] **Step 2: Produce assets with sips**

```bash
mkdir -p site/assets

# Icon set from the 1024 master
sips -Z 256 Design/icon-1024.png --out site/assets/icon-256.png
sips -Z 180 Design/icon-1024.png --out site/assets/apple-touch-icon.png
sips -Z 32  Design/icon-1024.png --out site/assets/favicon-32.png
sips -Z 16  Design/icon-1024.png --out site/assets/favicon-16.png

# Screenshots → max 1600px wide JPEG (quality ~80)
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_shapes.png"      --out site/assets/hero-shapes.jpg
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_zoomed.png"      --out site/assets/zoom.jpg
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_break_timer.jpeg" --out site/assets/break-timer.jpg
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_text.jpeg"       --out site/assets/text.jpg
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_snip.jpeg"       --out site/assets/snip.jpg
sips -Z 1600 -s format jpeg -s formatOptions 80 "Design/screenshot_menu.jpeg"       --out site/assets/menu.jpg
```

- [ ] **Step 3: Verify sizes**

Run: `ls -la site/assets/ && sips -g pixelWidth site/assets/hero-shapes.jpg`
Expected: every jpg well under 500 KB; hero width 1600.

- [ ] **Step 4: Commit**

```bash
git add site/assets
git commit -m "Add web assets for marketing site

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Page (HTML + CSS + JS) and deploy note

**Files:**
- Create: `site/index.html`, `site/style.css`, `site/script.js`
- Modify: `README.md` (deploy note in the Release section)

**Interfaces:**
- Consumes: asset filenames from Task 1.

- [ ] **Step 1: Write `site/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ZoomIt4Mac — screen zoom, annotation & recording for macOS</title>
  <meta name="description" content="A free, open-source, native macOS re-implementation of Sysinternals ZoomIt: screen zoom, drawing, break timer, screen recording and snipping from your menu bar.">
  <link rel="icon" type="image/png" sizes="32x32" href="assets/favicon-32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="assets/favicon-16.png">
  <link rel="apple-touch-icon" href="assets/apple-touch-icon.png">
  <meta property="og:title" content="ZoomIt4Mac">
  <meta property="og:description" content="The Sysinternals ZoomIt experience — native on your Mac. Zoom, draw, record, snip.">
  <meta property="og:image" content="https://zoomit4mac.corti.com/assets/hero-shapes.jpg">
  <meta property="og:url" content="https://zoomit4mac.corti.com/">
  <meta property="og:type" content="website">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="stylesheet" href="style.css">
</head>
<body>

<header class="hero">
  <img class="hero-icon" src="assets/icon-256.png" alt="ZoomIt4Mac app icon" width="128" height="128">
  <h1>ZoomIt4Mac</h1>
  <p class="tagline">The Sysinternals ZoomIt experience — native on your Mac.</p>
  <p class="subline">Zoom, draw, record and snip your screen straight from the menu bar.<br>
     Free &amp; open source · macOS 14+ · Apple silicon &amp; Intel</p>
  <div class="cta">
    <a id="download-dmg" class="button primary" href="https://github.com/TechPreacher/ZoomIt4Mac/releases/latest">
      Download .dmg <span id="release-version" hidden></span>
    </a>
    <a class="button" href="https://github.com/TechPreacher/ZoomIt4Mac">View on GitHub</a>
  </div>
  <div class="brew">
    <code>brew install TechPreacher/tap/zoomit4mac</code>
    <button id="copy-brew" type="button" hidden>Copy</button>
  </div>
  <img class="hero-shot" src="assets/hero-shapes.jpg"
       alt="ZoomIt4Mac draw mode: arrows, shapes and highlighter strokes over a desktop, with a blurred region hiding text">
</header>

<main>
  <section class="features" aria-label="Features">
    <article class="card">
      <img src="assets/zoom.jpg" alt="A frozen screen magnified around the cursor">
      <h2>Zoom <kbd>⌃1</kbd></h2>
      <p>Freeze the screen and glide from 1× to 8×. Move the mouse to pan — every pixel of every edge is reachable. Live Zoom <kbd>⌃4</kbd> does the same on moving content.</p>
    </article>
    <article class="card">
      <img src="assets/hero-shapes.jpg" alt="Freehand strokes, straight lines, arrows and rectangles drawn over the screen">
      <h2>Draw <kbd>⌃2</kbd></h2>
      <p>Freehand pen, lines, arrows, rectangles, ellipses in six colors — plus a translucent highlighter <kbd>H</kbd> and a blur pen <kbd>X</kbd> for hiding what the audience shouldn’t read.</p>
    </article>
    <article class="card">
      <img src="assets/text.jpg" alt="Large text typed directly onto the screen">
      <h2>Type <kbd>T</kbd></h2>
      <p>Click anywhere and type on the screen. Resize on the fly with <kbd>⌘+</kbd> and <kbd>⌘−</kbd>.</p>
    </article>
    <article class="card">
      <img src="assets/break-timer.jpg" alt="A large countdown timer over a faded desktop">
      <h2>Break Timer <kbd>⌃3</kbd></h2>
      <p>A full-screen countdown for workshop breaks — configurable duration, position, background and end-of-break sound.</p>
    </article>
    <article class="card">
      <img src="assets/snip.jpg" alt="A bright selection rectangle over a dimmed screen with size label">
      <h2>Snip <kbd>⌃6</kbd></h2>
      <p>Freeze, drag, release — the region lands on your clipboard. Hold <kbd>⌥</kbd> to save a PNG as well.</p>
    </article>
    <article class="card">
      <img src="assets/menu.jpg" alt="The ZoomIt4Mac menu bar menu with all commands">
      <h2>Always one keystroke away</h2>
      <p>Screen Recording <kbd>⌃5</kbd> with optional microphone and system audio, every mode in the menu bar, rebindable hotkeys with conflict detection, a shortcuts reference panel and launch at login.</p>
    </article>
  </section>

  <section class="install" aria-label="Install">
    <h2>Install</h2>
    <div class="install-grid">
      <div>
        <h3>DMG</h3>
        <p>Download, open, drag <strong>ZoomIt4Mac</strong> to Applications. Signed and notarized.</p>
      </div>
      <div>
        <h3>Homebrew</h3>
        <p><code>brew install TechPreacher/tap/zoomit4mac</code><br>
        First time: <code>brew trust techpreacher/tap</code></p>
      </div>
      <div>
        <h3>Permissions</h3>
        <p>Zoom, Live Zoom, Snip and Recording ask for <em>Screen Recording</em> once. Microphone is separate and optional. No Accessibility access needed.</p>
      </div>
    </div>
  </section>
</main>

<footer>
  <p><a href="https://github.com/TechPreacher/ZoomIt4Mac">GitHub</a> ·
     <a href="https://github.com/TechPreacher/ZoomIt4Mac/blob/main/LICENSE">MIT License</a> ·
     © 2026 Sascha Corti</p>
  <p class="fineprint">ZoomIt is a <a href="https://learn.microsoft.com/sysinternals/">Sysinternals</a> tool by Mark Russinovich; ZoomIt and Sysinternals are trademarks of Microsoft Corporation. ZoomIt4Mac is an independent re-implementation for macOS and is not affiliated with or endorsed by Microsoft.</p>
</footer>

<script src="script.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write `site/script.js`**

```js
// Progressive enhancement only — the page works without any of this.
(function () {
  "use strict";

  // Point the download button at the newest .dmg release asset.
  var button = document.getElementById("download-dmg");
  var version = document.getElementById("release-version");
  fetch("https://api.github.com/repos/TechPreacher/ZoomIt4Mac/releases/latest")
    .then(function (r) { return r.ok ? r.json() : Promise.reject(new Error(r.status)); })
    .then(function (release) {
      var dmg = (release.assets || []).filter(function (a) {
        return /\.dmg$/.test(a.name);
      })[0];
      if (dmg && button) button.href = dmg.browser_download_url;
      if (version && release.tag_name) {
        version.textContent = release.tag_name.replace(/^v/, "");
        version.hidden = false;
      }
    })
    .catch(function () { /* keep the static releases-page link */ });

  // Copy button for the brew command.
  var copy = document.getElementById("copy-brew");
  if (copy && navigator.clipboard) {
    copy.hidden = false;
    copy.addEventListener("click", function () {
      navigator.clipboard.writeText("brew install TechPreacher/tap/zoomit4mac").then(function () {
        copy.textContent = "Copied!";
        setTimeout(function () { copy.textContent = "Copy"; }, 1500);
      });
    });
  }
})();
```

- [ ] **Step 3: Write `site/style.css`**

```css
:root {
  --accent: #d23c3c;
  --bg: #ffffff;
  --bg-raised: #f6f6f7;
  --text: #1d1d1f;
  --text-dim: #6e6e73;
  --border: #e3e3e6;
  --shadow: 0 8px 30px rgba(0, 0, 0, 0.10);
  color-scheme: light dark;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #101012;
    --bg-raised: #1b1b1f;
    --text: #f5f5f7;
    --text-dim: #98989d;
    --border: #2c2c31;
    --shadow: 0 8px 30px rgba(0, 0, 0, 0.5);
  }
}

* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  background: var(--bg);
  color: var(--text);
  line-height: 1.55;
}
img { max-width: 100%; height: auto; display: block; }
a { color: var(--accent); }

.hero {
  max-width: 960px;
  margin: 0 auto;
  padding: 64px 24px 32px;
  text-align: center;
}
.hero-icon { margin: 0 auto 16px; }
.hero h1 { font-size: 44px; margin: 0 0 8px; letter-spacing: -0.02em; }
.tagline { font-size: 21px; color: var(--text); margin: 0 0 4px; }
.subline { color: var(--text-dim); margin: 0 0 28px; }

.cta { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; margin-bottom: 16px; }
.button {
  display: inline-block;
  padding: 12px 22px;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: var(--bg-raised);
  color: var(--text);
  text-decoration: none;
  font-weight: 600;
}
.button.primary {
  background: var(--accent);
  border-color: var(--accent);
  color: #fff;
}
.button:hover { filter: brightness(1.06); }
#release-version { font-weight: 400; opacity: 0.85; margin-left: 6px; }
#release-version::before { content: "v"; }

.brew {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  background: var(--bg-raised);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 8px 14px;
  margin-bottom: 40px;
}
.brew code { font-size: 14px; }
.brew button {
  border: none;
  background: var(--accent);
  color: #fff;
  border-radius: 7px;
  padding: 4px 10px;
  font-size: 13px;
  cursor: pointer;
}

.hero-shot {
  border-radius: 14px;
  box-shadow: var(--shadow);
  border: 1px solid var(--border);
}

main { max-width: 960px; margin: 0 auto; padding: 24px; }

.features {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  margin: 40px 0 64px;
}
@media (max-width: 720px) {
  .features { grid-template-columns: 1fr; }
  .hero h1 { font-size: 34px; }
}
.card {
  background: var(--bg-raised);
  border: 1px solid var(--border);
  border-radius: 14px;
  overflow: hidden;
}
.card img { border-bottom: 1px solid var(--border); aspect-ratio: 3024 / 1964; object-fit: cover; }
.card h2 { font-size: 20px; margin: 16px 18px 6px; }
.card p { margin: 0 18px 18px; color: var(--text-dim); font-size: 15px; }

kbd {
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 0.8em;
  background: var(--bg);
  border: 1px solid var(--border);
  border-bottom-width: 2px;
  border-radius: 6px;
  padding: 1px 7px;
  vertical-align: middle;
  white-space: nowrap;
}

.install { margin-bottom: 64px; }
.install h2 { font-size: 28px; text-align: center; margin-bottom: 24px; }
.install-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 24px;
}
@media (max-width: 720px) {
  .install-grid { grid-template-columns: 1fr; }
}
.install-grid > div {
  background: var(--bg-raised);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 18px;
}
.install-grid h3 { margin: 0 0 8px; }
.install-grid p { margin: 0; color: var(--text-dim); font-size: 15px; }
.install-grid code { font-size: 13px; word-break: break-all; }

footer {
  border-top: 1px solid var(--border);
  padding: 28px 24px 40px;
  text-align: center;
  color: var(--text-dim);
  font-size: 14px;
}
.fineprint { font-size: 12px; max-width: 640px; margin: 8px auto 0; }
```

- [ ] **Step 4: README deploy note**

In `README.md`, append to the `## Release` section (after the cask step):

```markdown

The marketing site at [zoomit4mac.corti.com](https://zoomit4mac.corti.com) is the static page in [`site/`](site/) — deploy by copying its contents to the web server. Download links resolve the latest GitHub release automatically; no per-release site update needed.
```

- [ ] **Step 5: Verify locally**

```bash
open site/index.html   # visual check
python3 -c "import html.parser, pathlib; p = html.parser.HTMLParser(); p.feed(pathlib.Path('site/index.html').read_text()); print('parsed ok')"
```
Expected: page renders; light/dark follow system; at 375 px width no horizontal scroll; images load; button href resolves to the v1.0.0 dmg after load (needs network); copy button appears and copies. Report which checks were done by eye.

- [ ] **Step 6: Commit**

```bash
git add site/index.html site/style.css site/script.js README.md
git commit -m "Add marketing website

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
