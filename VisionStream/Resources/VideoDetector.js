// Runs in WKContentWorld.defaultClient in every permitted frame. Only reads DOM media.
(() => {
  "use strict";
  if (globalThis.visionStreamDetector) return;
  const frameID = globalThis.crypto?.randomUUID?.() || String(Math.random());
  const ids = new WeakMap();
  const encrypted = new WeakSet();
  const watched = new WeakSet();
  const playIntents = new WeakMap();
  let sequence = 0;
  let timer = null;
  let latest = [];
  const text = (value, length = 4096) => String(value || "").slice(0, length);
  // Empty URL attributes resolve to the document URL in WebKit. Reading .src
  // alone can advertise the HTML page itself as an MP4/HLS stream.
  const hasSource = node => Boolean(node.getAttribute("src")?.trim());
  function videos() {
    const found = [];
    function visit(root) {
      for (const node of root.querySelectorAll("video")) found.push(node);
      // Open shadow roots only. Closed roots and inaccessible frames are not circumvented.
      for (const node of root.querySelectorAll("*")) if (node.shadowRoot) visit(node.shadowRoot);
    }
    visit(document);
    return found.slice(0, 16);
  }
  function visible(video) {
    const rect = video.getBoundingClientRect(), style = getComputedStyle(video);
    return !video.hidden && style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0 &&
      rect.width >= 120 && rect.height >= 68 && rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight;
  }
  function advertisement(video) {
    // Only explicit DOM ad markers, never guesses based on a site's name or
    // short duration. A generic detector cannot identify every site's adverts.
    return Boolean(video.closest('[data-ad]:not([data-ad="false"]):not([data-ad="0"]), [data-ad-slot], [data-ad-playing="true"], .video-ad, .ad-container, .vjs-ad-playing, .jw-flag-ads, [aria-label="Advertisement" i]'));
  }
  function rememberPlay(event) {
    if (!event.isTrusted || document.visibilityState !== "visible" || event.repeat) return;
    const path = event.composedPath?.() || [event.target];
    const target = path.find(node => node instanceof Element);
    if (!target || target.closest('input, textarea, select, [contenteditable="true"]')) return;
    const paused = videos().filter(video => !advertisement(video) && (video.paused || video.ended));
    const eligible = paused.filter(visible);
    let selected = eligible.find(video => path.includes(video));
    if (!selected && event.type !== "keydown") {
      const x = event.clientX, y = event.clientY;
      // Works with play overlays, including sibling custom controls placed over
      // the actual visible video. Clicking elsewhere on the page is not intent.
      selected = eligible.filter(video => {
        const rect = video.getBoundingClientRect();
        return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
      }).sort((a,b) => b.getBoundingClientRect().width*b.getBoundingClientRect().height-a.getBoundingClientRect().width*a.getBoundingClientRect().height)[0];
      if (!selected && target.closest('button, [role="button"]')) {
        const player = target.closest('.video-js, .plyr, .jwplayer, [data-player], [class*="video-player"], [id*="video-player"]');
        const local = paused.filter(video => player?.contains(video));
        if (local.length === 1) selected = local[0];
      }
    }
    if (!selected && event.type === "keydown" && [" ", "Enter"].includes(event.key)) {
      const player = target.closest('.video-js, .plyr, .jwplayer, [data-player]');
      const local = paused.filter(video => player?.contains(video));
      if (local.length === 1) selected = local[0];
    }
    if (!selected) return;
    const previous = playIntents.get(selected), now = performance.now();
    // pointerdown and click belong to the same activation, not two launches.
    if (!previous || now-previous.time > 700) {
      const id = globalThis.crypto?.randomUUID?.() || "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
        const value = Math.floor(Math.random()*16);return (c === "x" ? value : (value&3)|8).toString(16);
      });
      playIntents.set(selected, {id, time:now});
    }
    schedule();
  }
  document.addEventListener("pointerdown", rememberPlay, true);
  document.addEventListener("click", rememberPlay, true);
  document.addEventListener("keydown", event => { if ([" ", "Enter"].includes(event.key)) rememberPlay(event); }, true);
  function scan() {
    timer = null;
    const candidates = [];
    for (const video of videos()) {
      if (!ids.has(video)) ids.set(video, "video-" + (++sequence));
      if (!watched.has(video)) {
        watched.add(video);
        for (const name of ["loadedmetadata", "play", "playing", "emptied", "durationchange", "error", "waiting", "stalled", "pause", "ended"])
          video.addEventListener(name, schedule);
        video.addEventListener("encrypted", () => { encrypted.add(video); schedule(); });
      }
      let sources = [];
      // currentSrc is authoritative. Do not advertise unused fallback URLs for blob playback.
      if (video.currentSrc) {
        const match = Array.from(video.querySelectorAll("source")).find(s => s.src === video.currentSrc);
        sources = [{ src: video.currentSrc, type: match?.type || video.getAttribute("type") || "" }];
      } else if (hasSource(video) && video.src) {
        sources = [{ src: video.src, type: video.getAttribute("type") || "" }];
      } else {
        sources = Array.from(video.querySelectorAll("source")).filter(hasSource).slice(0, 4).map(s => ({src: s.src, type: s.type}));
      }
      for (const source of sources) {
        if (!source.src || source.src.length > 16384) continue;
        const videoID = ids.get(video);
        candidates.push({
          id: frameID + ":" + videoID + ":" + candidates.length,
          videoID, source: source.src, mimeType: text(source.type, 128),
          title: text(video.title || document.title || "Video", 160), pageURL: text(location.href),
          encrypted: encrypted.has(video) || Boolean(video.mediaKeys),
          width: video.videoWidth || 0, height: video.videoHeight || 0,
          currentTime: Number.isFinite(video.currentTime) ? Math.max(0, video.currentTime) : 0,
          formatHint: (() => {
            const projectionName = text(video.getAttribute("data-projection"), 40).toLowerCase();
            const fov = text(video.getAttribute("data-fov"), 10);
            const stereo = text(video.getAttribute("data-stereo"), 40).toLowerCase();
            const projection = ["vr180", "180"].includes(projectionName) || (projectionName === "equirectangular" && fov === "180") ? "vr180" :
              ["vr360", "360"].includes(projectionName) || (projectionName === "equirectangular" && fov === "360") ? "vr360" : null;
            const layout = ["sbs", "side-by-side", "sideBySide".toLowerCase()].includes(stereo) ? "sideBySide" :
              ["tb", "top-bottom", "over-under"].includes(stereo) ? "topBottom" : stereo === "mono" ? "mono" : null;
            return projection || layout ? {projection, layout, evidence: "metadata"} : null;
          })(),
          webMedia: { errorCode: video.error?.code || 0, readyState: video.readyState,
            networkState: video.networkState, paused: Boolean(video.paused) },
          playIntent: (() => {
            const intent = playIntents.get(video);
            if (!intent || advertisement(video) || performance.now()-intent.time > 30000) return null;
            return {id:intent.id, age:Math.max(0,(performance.now()-intent.time)/1000), visible:visible(video)};
          })()
        });
      }
    }
    latest = candidates.slice(0, 16);
    globalThis.webkit?.messageHandlers?.visionStream?.postMessage({frameID, candidates: latest});
    return latest;
  }
  function schedule() {
    if (timer === null) timer = setTimeout(scan, 200);
  }
  function pause(videoID, source) {
    const video = videos().find(v => ids.get(v) === videoID);
    if (!video || (video.currentSrc || video.src) !== source) return false;
    video.pause();
    return true;
  }
  globalThis.visionStreamDetector = {scan, pause};
  new MutationObserver(schedule).observe(document, {subtree: true, childList: true, attributes: true, attributeFilter: ["src", "type"]});
  setInterval(scan, 1500);
  scan();
})();
