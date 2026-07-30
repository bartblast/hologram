"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-uncaught-error-overlay";

// The overlay reporting an uncaught client error in the page. Dismissable,
// since a runtime error often leaves the rest of the page usable.
export default class UncaughtErrorOverlay {
  static hide() {
    ErrorOverlay.hide(OVERLAY_ID);
  }

  static show(content) {
    ErrorOverlay.show({
      content,
      dismissable: true,
      heading: "Runtime Error",
      id: OVERLAY_ID,
    });
  }
}
