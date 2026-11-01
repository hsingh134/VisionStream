// Observer-only early error metadata in WebKit's isolated client world.
// No console patching, messages, page content or intercepted network requests.
(() => {
  "use strict";
  if (globalThis.visionStreamTestingBootstrap) return;
  const errors = [];
  window.addEventListener("error", event => {
    errors.push({name:event.error?.name || "resource-error", source:event.filename || event.target?.src || null,
      line:event.lineno || 0, column:event.colno || 0, timeMs:performance.timeOrigin + performance.now()});
    if (errors.length > 16) errors.shift();
  }, true);
  globalThis.visionStreamTestingBootstrap = {errors};
})();
