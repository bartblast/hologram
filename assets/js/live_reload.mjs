"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

// The client half of live reload: reloading the page once the server has
// recompiled, and reporting a compilation error until it does.
export default class LiveReload {
  // The pages a live reload rebuilt since this document loaded, other than the one it
  // shows. A bundle of one that this tab holds from an earlier visit is out of date.
  static stalePageModules = new Set();

  // The pages arrive as the server names them ("Elixir.MyApp.HomePage"), which is the
  // value of the boxed page module atom. The tab reloads when its own page is among them,
  // or when every tab must, because the runtime script it runs was rebuilt.
  static handleReload(pages, currentPageModule) {
    if (pages === "all" || pages.includes(currentPageModule.value)) {
      $.reload();
      return;
    }

    for (const page of pages) {
      $.stalePageModules.add(page);
    }
  }

  static isStale(pageModule) {
    return $.stalePageModules.has(pageModule.value);
  }

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

const $ = LiveReload;
