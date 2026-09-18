"use strict";

import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

// The client half of live reload: reloading the page once the server has
// recompiled, reporting a compilation error until it does, and telling when a
// page's code this tab holds from an earlier visit has been rebuilt since.
export default class LiveReload {
  // The digest of the bundle this tab loaded for each page, by the page module's
  // value. A bundle is named by the digest of its content, so a page the server
  // now serves under another digest has code this tab holds in an older version.
  static pageBundleDigests = new Map();

  // The pages arrive as the server names them ("Elixir.MyApp.HomePage"), which is the
  // value of the boxed page module atom. The tab reloads when its own page is among them,
  // or when every tab must, because the runtime script it runs was rebuilt.
  static handleReload(pages, currentPageModule) {
    if (pages === "all" || pages.includes(currentPageModule.value)) {
      $.reload();
    }
  }

  // Whether this tab holds the page's code under a digest other than the given one, the
  // digest the server serves the page under now. Answered only where live reload runs:
  // elsewhere a digest can change only with a deploy, which is not this module's concern.
  static holdsOldPageBundle(pageModule, pageDigest) {
    if (!globalThis.Hologram.config.liveReload) {
      return false;
    }

    const heldDigest = $.pageBundleDigests.get(pageModule.value);

    return heldDigest !== undefined && heldDigest !== pageDigest;
  }

  // The digest of the bundle this tab loaded for the page, or null when it loaded none.
  static heldPageDigest(pageModule) {
    if (pageModule === null) {
      return null;
    }

    return $.pageBundleDigests.get(pageModule.value) ?? null;
  }

  static recordPageBundle(pageModule, pageDigest) {
    $.pageBundleDigests.set(pageModule.value, pageDigest);
  }

  static reload() {
    document.location.reload();
  }

  // Whether a page snapshot can be restored into the code given by the page digest and the
  // runtime bundle path: the snapshot holds component state shaped by the code it was taken
  // with, and component code lives in the page bundle and, for components the runtime
  // carries, in the runtime bundle. A snapshot with no stamp, taken before stamping existed
  // or before any bundle was recorded, is taken on trust, as every snapshot used to be.
  static snapshotFits(snapshot, pageDigest, runtimeBundlePath) {
    if (!globalThis.Hologram.config.liveReload) {
      return true;
    }

    if (snapshot.pageDigest === undefined || snapshot.pageDigest === null) {
      return true;
    }

    return (
      snapshot.pageDigest === pageDigest &&
      snapshot.runtimeBundlePath === runtimeBundlePath
    );
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
