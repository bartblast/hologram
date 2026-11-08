"use strict";

import AssetPathRegistry from "./asset_path_registry.mjs";
import ErrorOverlay from "./error_overlay.mjs";

const OVERLAY_ID = "hologram-live-reload-error-overlay";

// The query param a swapped stylesheet's URL carries, so that the browser fetches it afresh.
const SWAP_PARAM = "_hologram_css";

// The client half of live reload: reloading the page once the server has
// recompiled, reporting a compilation error until it does, and telling when a
// page's code this tab holds from an earlier visit has been rebuilt since.
export default class LiveReload {
  // The digest of the bundle this tab loaded for each page, by the page module's
  // value. A bundle is named by the digest of its content, so a page the server
  // now serves under another digest has code this tab holds in an older version.
  static pageBundleDigests = new Map();

  // The copies a swap adds while it runs, which are not swapped themselves.
  static #swapCopies = new WeakSet();

  // The stylesheet links being swapped, each with whether another swap was asked
  // for meanwhile.
  static #swaps = new WeakMap();

  // Counts the swaps, so that two swaps in the same millisecond get different URLs.
  static #swapCount = 0;

  // The pages arrive as the server names them ("Elixir.MyApp.HomePage"), which is the
  // value of the boxed page module atom. The tab reloads when its own page is among them,
  // or when every tab must: the runtime or chunk scripts were rebuilt, or an asset of the
  // app other than CSS changed.
  static handleReload(pages, currentPageModule) {
    if (pages === "all" || pages.includes(currentPageModule.value)) {
      $.reload();
    }
  }

  // Taken down once a live reload compiled, whether or not it rebuilt the page this
  // tab shows: a rebuilt page reloads the tab, which takes the overlay down with the
  // document, and a live reload that left the page as it was still compiled the code
  // the error was in.
  static hideErrorOverlay() {
    ErrorOverlay.hide(OVERLAY_ID);
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

  // Phoenix's live reload runs in an iframe its plug adds to every page, and reloads the tab on
  // any change to a file its patterns match, Hologram's own bundles among them. Where Hologram's
  // live reload runs, it does that job for the page, so the iframe goes before the page renders.
  // Where it does not, Phoenix's is the only one, so the iframe stays. The iframe is told by its
  // path, which an endpoint path prefix or the :suffix option only add to.
  static removePhoenixReloader() {
    if (!globalThis.Hologram.config.liveReload) {
      return;
    }

    document
      .querySelectorAll('iframe[src*="/phoenix/live_reload/frame"]')
      .forEach((iframe) => iframe.remove());
  }

  // Whether a page snapshot can be restored into the code given by the page digest and the
  // runtime digest: the snapshot holds component state shaped by the code it was taken
  // with, and component code lives in the page bundle and, for components the runtime
  // carries, in the runtime bundle. A snapshot with no stamp, taken before stamping existed
  // or before any bundle was recorded, is taken on trust, as every snapshot used to be.
  static snapshotFits(snapshot, pageDigest, runtimeDigest) {
    if (!globalThis.Hologram.config.liveReload) {
      return true;
    }

    if (snapshot.pageDigest === undefined || snapshot.pageDigest === null) {
      return true;
    }

    return (
      snapshot.pageDigest === pageDigest &&
      snapshot.runtimeDigest === runtimeDigest
    );
  }

  // Loads the app's CSS afresh, without reloading the page. The stylesheets come from the
  // app's own static files, so a stylesheet from another origin is left alone, and so is
  // one marked data-no-reload, the attribute Phoenix's live reload skips too.
  //
  // The app's asset paths come with a CSS change, by static path, as the server has them
  // then, and the asset path registry takes them, so that a later render links them. A
  // stylesheet whose asset the registry now names by another path, such as the plain file once
  // a digested copy no longer holds its content, is swapped to that path.
  static swapStylesheets(appAssetManifest = null) {
    if (appAssetManifest !== null) {
      $.#takeAppAssetPaths(appAssetManifest);
    }

    const pageOrigin = document.location.origin;

    document.querySelectorAll('link[rel="stylesheet"]').forEach((link) => {
      if (
        !$.#swapCopies.has(link) &&
        !link.hasAttribute("data-no-reload") &&
        new URL(link.href).origin === pageOrigin
      ) {
        $.#swapStylesheet(link);
      }
    });
  }

  static #freshStylesheetUrl(link) {
    const url = new URL(link.href);
    const newestPath = $.#newestAssetPath(url.pathname);

    if (newestPath !== null) {
      url.pathname = newestPath;
    }

    url.searchParams.set(SWAP_PARAM, `${Date.now()}-${++$.#swapCount}`);

    return url.toString();
  }

  // The path the asset path registry names the asset linked by the given URL path by, when it is
  // another one, else null. The asset is told by its static path, the URL path with the leading
  // slash and the digest `mix phx.digest` names a copy with taken off, read the way the server
  // reads it, so that a stylesheet linked by any copy of the asset, or by a path the registry no
  // longer holds, finds the asset's path. A URL path that can't be decoded, or an asset the
  // registry doesn't know, is left as it is.
  static #newestAssetPath(urlPath) {
    if (AssetPathRegistry.manifest === null) {
      return null;
    }

    let path;

    try {
      path = decodeURIComponent(urlPath);
    } catch {
      return null;
    }

    const relativePath = path.replace(/^\//, "");
    const digestMatch = relativePath.match(/^(.+)-([0-9a-f]{32})(.+)$/);
    const staticPath = digestMatch
      ? digestMatch[1] + digestMatch[3]
      : relativePath;
    const assetPath = AssetPathRegistry.manifest[staticPath];

    return assetPath !== undefined && assetPath !== path ? assetPath : null;
  }

  // The link element stays: the virtual DOM holds it, so it is given the fresh URL rather than
  // replaced. A copy loads the fresh stylesheet first and keeps the page styled while the
  // link loads it again, from the cache, which leaves no moment without the styles. A copy
  // that fails to load leaves the link as it is: a link whose new URL fails loses its styles.
  //
  // The virtual DOM keeps the old URL in its vnode, but it patches attributes from vnode to
  // vnode, so a later render with the same URL leaves the fresh one in place. A render that
  // removes the link, or recreates it, which it does when the URL in the template changes,
  // ends the swap: the browser fires no event for a link that left the document.
  static #swapStylesheet(link) {
    const runningSwap = $.#swaps.get(link);

    if (runningSwap) {
      runningSwap.isAskedAgain = true;
      return;
    }

    // A disabled stylesheet applies to nothing, so it takes the fresh URL right away, with no
    // copy. One disabled by its attribute is not loaded at all, and neither it nor a copy would
    // fire an event; it loads the fresh URL once enabled. One disabled through its style sheet
    // object gets a new, enabled one with the URL, which is disabled again once it loads.
    const isSheetDisabled = link.sheet?.disabled === true;

    if (link.hasAttribute("disabled") || isSheetDisabled) {
      if (isSheetDisabled) {
        link.addEventListener(
          "load",
          () => {
            if (link.sheet) link.sheet.disabled = true;
          },
          {once: true},
        );
      }

      link.href = $.#freshStylesheetUrl(link);
      return;
    }

    const freshUrl = $.#freshStylesheetUrl(link);
    const swap = {isAskedAgain: false};

    // Every listener is removed once the swap ends: one left on the link would answer a later
    // swap's event.
    const listenerRemovals = [];

    const listen = (element, type, listener) => {
      element.addEventListener(type, listener);

      listenerRemovals.push(() => element.removeEventListener(type, listener));
    };

    $.#swaps.set(link, swap);

    const copy = link.cloneNode();
    $.#swapCopies.add(copy);
    // The browser hides a nonce attribute once the element is in the document, so it is read
    // from the property, which keeps it.
    copy.nonce = link.nonce || link.getAttribute("nonce") || "";
    copy.href = freshUrl;

    const observer = new MutationObserver(() => {
      if (!link.isConnected) {
        finish();
      }
    });

    const finish = () => {
      listenerRemovals.forEach((removeListener) => removeListener());
      observer.disconnect();
      copy.remove();
      $.#swaps.delete(link);

      if (swap.isAskedAgain) {
        // A link a render recreated meanwhile is another element, found anew.
        if (link.isConnected) {
          $.#swapStylesheet(link);
        } else {
          $.swapStylesheets();
        }
      }
    };

    const onCopyLoaded = () => {
      listen(link, "load", finish);
      listen(link, "error", finish);
      link.href = freshUrl;
    };

    listen(copy, "load", onCopyLoaded);
    listen(copy, "error", finish);

    observer.observe(link.parentNode, {childList: true});
    link.after(copy);
  }

  static #takeAppAssetPaths(appAssetManifest) {
    if (AssetPathRegistry.entries === null) {
      AssetPathRegistry.populate(globalThis.Hologram.assetManifest);
    }

    AssetPathRegistry.replaceAppEntries(appAssetManifest);
  }

  // The diagnostic arrives already read into lines of toned segments. The
  // server has the compiler's output in hand, so it works out how the lines
  // read and nothing here has to make sense of them.
  //
  // Not dismissable: a compilation error leaves the page meaningless, and the
  // overlay goes away once a live reload compiles.
  static showErrorOverlay(lines) {
    ErrorOverlay.show({
      content: lines,
      heading: "Compilation Error",
      id: OVERLAY_ID,
    });
  }
}

const $ = LiveReload;
