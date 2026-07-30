"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

// The client half of live reload: reloading the page once the server has
// recompiled, and reporting a compilation error until it does.
export default class LiveReload {
  static reload() {
    document.location.reload();
  }

  // Not dismissable: a compilation error leaves the page meaningless, and the
  // overlay goes away when a successful recompilation reloads the page.
  static showErrorOverlay(content) {
    ErrorOverlay.show({
      content,
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });
  }
}
