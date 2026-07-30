"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

export default class LiveReload {
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
