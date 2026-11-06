// Runs in WKContentWorld.defaultClient in every permitted frame. Only reads DOM media.
(() => {
  "use strict";
  if (globalThis.visionStreamDetector) return;
  const frameID = globalThis.crypto?.randomUUID?.() || String(Math.random());
  const ids = new WeakMap();
  const encrypted = new WeakSet();
  const watched = new WeakSet();
  const playIntents = new WeakMap();
  const videoEvents = new WeakMap();
  const scriptErrors = globalThis.visionStreamTestingBootstrap?.errors || [];
  const epoch = () => performance.timeOrigin + performance.now();
  if (!globalThis.visionStreamTestingBootstrap) window.addEventListener("error", event => {
    scriptErrors.push({name: event.error?.name || "resource-error", source: event.filename || event.target?.src || null, line: event.lineno || 0, column: event.colno || 0, timeMs: epoch()});
    if (scriptErrors.length > 16) scriptErrors.shift();
  }, true);
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
  function visibleElement(video, minimumWidth, minimumHeight) {
    const rect = video.getBoundingClientRect(), style = getComputedStyle(video);
    return !video.hidden && style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0 &&
      rect.width >= minimumWidth && rect.height >= minimumHeight && rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight;
  }
  function visible(video) { return visibleElement(video, 120, 68); }
  function surface(video) {
    if (visible(video)) return video;
    // A canvas player can keep its decoder video hidden as a texture source.
    // Only associate a visible canvas inside an explicit, single-video player.
    const player = video.closest('.video-js, .plyr, .jwplayer, [data-player], a-scene, [class*="video-player"], [id*="video-player"]');
    if (!player || player.querySelectorAll("video").length !== 1) return null;
    const canvases = Array.from(player.querySelectorAll("canvas")).filter(visible);
    return canvases.length === 1 ? canvases[0] : null;
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
    const eligible = paused.filter(video => surface(video));
    let selected = eligible.find(video => path.includes(video) || path.includes(surface(video)));
    if (!selected && event.type !== "keydown") {
      const x = event.clientX, y = event.clientY;
      // Works with play overlays, including sibling custom controls placed over
      // the actual visible video. Clicking elsewhere on the page is not intent.
      selected = eligible.filter(video => {
        const rect = surface(video).getBoundingClientRect();
        return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
      }).sort((a,b) => surface(b).getBoundingClientRect().width*surface(b).getBoundingClientRect().height-surface(a).getBoundingClientRect().width*surface(a).getBoundingClientRect().height)[0];
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
        for (const name of ["loadedmetadata", "loadeddata", "play", "playing", "emptied", "durationchange", "error", "waiting", "stalled", "pause", "ended", "seeking", "seeked", "canplay", "canplaythrough"])
          video.addEventListener(name, () => {
            const events = videoEvents.get(video) || []; events.push({name, timeMs:epoch()});
            if (events.length > 32) events.shift(); videoEvents.set(video, events); schedule();
          });
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
      const presentation = surface(video);
      if (!sources.length && ((video.readyState || 0) > 0 || presentation?.tagName === "CANVAS"))
        sources = [{src:"", type:""}];
      for (const source of sources) {
        if (source.src.length > 16384) continue;
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
            networkState: video.networkState, paused: Boolean(video.paused),
            canvasBacked: Boolean(presentation && presentation !== video), adMarked: advertisement(video) },
          playIntent: (() => {
            const intent = playIntents.get(video);
            if (!intent || advertisement(video) || performance.now()-intent.time > 30000) return null;
            return {id:intent.id, age:Math.max(0,(performance.now()-intent.time)/1000), visible:Boolean(presentation)};
          })()
        });
      }
    }
    // Some XR players keep the HTMLVideoElement outside the document. A
    // visible canvas + explicit VR control + observed media request is enough
    // to offer source discovery, never to advertise a native stream or autoplay.
    if (!candidates.some(candidate => !candidate.webMedia.adMarked)) {
      const canvas = Array.from(document.querySelectorAll("canvas")).find(visible);
      const xrControl = Array.from(document.querySelectorAll('button, [role="button"], .a-enter-vr-button')).some(node =>
        visibleElement(node, 12, 12) && /\b(?:vr|webxr|virtual reality)\b/i.test([node.getAttribute("aria-label"), node.getAttribute("title"), node.textContent].join(" ")));
      const mediaRequest = performance.getEntriesByType("resource").slice(-64).some(entry => {
        try { return entry.initiatorType === "video" || /\.(?:mp4|m4v|m3u8|webm)$/i.test(new URL(entry.name,location.href).pathname); } catch { return false; }
      });
      if (canvas && xrControl && mediaRequest) candidates.unshift({id:frameID+":canvas-player",videoID:"",source:"",mimeType:"",
        title:text(document.title || "Browser VR player",160),pageURL:text(location.href),encrypted:false,width:0,height:0,currentTime:0,
        formatHint:null,playIntent:null,webMedia:{errorCode:0,readyState:0,networkState:0,paused:true,canvasBacked:true,adMarked:false}});
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
  function diagnostics() {
    const finite = value => Number.isFinite(value) ? value : null;
    const ranges = value => Array.from({length:Math.min(value.length,8)}, (_,i) => [value.start(i),value.end(i)]);
    const navigation = performance.getEntriesByType("navigation")[0];
    const timings = {};
    for (const key of ["startTime","duration","fetchStart","domainLookupStart","domainLookupEnd","connectStart","connectEnd","secureConnectionStart","requestStart","responseStart","responseEnd","domInteractive","domContentLoadedEventEnd","domComplete","loadEventEnd"]) if (navigation && Number.isFinite(navigation[key])) timings[key] = navigation[key];
    return {
      url:location.href, readyState:document.readyState, visibility:document.visibilityState, userAgent:navigator.userAgent,
      observedAtMs:epoch(), navigation:timings, scriptErrors,
      resources:performance.getEntriesByType("resource").slice(-64).map(r => ({url:r.name,initiator:r.initiatorType || "unknown",nextHop:r.nextHopProtocol || "unknown",startMs:r.startTime,durationMs:r.duration,requestStartMs:r.requestStart || 0,responseStartMs:r.responseStart || 0,responseEndMs:r.responseEnd || 0,transferBytes:r.transferSize || 0,encodedBytes:r.encodedBodySize || 0,decodedBytes:r.decodedBodySize || 0})),
      videos:videos().map(video => {
        const quality = video.getVideoPlaybackQuality?.();
        return {videoID:ids.get(video) || "",source:video.currentSrc || (hasSource(video) ? video.src : null),attributeSource:hasSource(video) ? video.src : null,
          readyState:video.readyState,networkState:video.networkState,errorCode:video.error?.code || 0,paused:video.paused,muted:video.muted,visible:visible(video),adMarked:advertisement(video),
          width:video.videoWidth,height:video.videoHeight,currentTime:finite(video.currentTime) || 0,duration:finite(video.duration),frames:quality?.totalVideoFrames ?? null,droppedFrames:quality?.droppedVideoFrames ?? null,
          buffered:ranges(video.buffered),seekable:ranges(video.seekable),events:videoEvents.get(video) || []};
      })
    };
  }
  globalThis.visionStreamDetector = {scan, pause, diagnostics};
  new MutationObserver(schedule).observe(document, {subtree: true, childList: true, attributes: true, attributeFilter: ["src", "type"]});
  setInterval(scan, 1500);
  scan();
})();
