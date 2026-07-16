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
