"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

// The client half of live reload: reloading the page once the server has
// recompiled, and reporting a compilation error until it does.
export default class LiveReload {
  static reload() {
    document.location.reload();
  }

  // The diagnostic arrives already read into lines of toned segments. The
  // server has the compiler's output in hand, so it works out how the lines
  // read and nothing here has to make sense of them.
  //
  // Not dismissable: a compilation error leaves the page meaningless, and the
  // overlay goes away when a successful recompilation reloads the page.
  static showErrorOverlay(lines) {
    ErrorOverlay.show({
      content: lines,
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });
  }
}
