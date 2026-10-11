"use strict";

import ScriptRegistry from "./script_registry.mjs";

// What stands between a page and its mount: the scripts the page needs, named by their digests
// (see ScriptRegistry), and the mount that waits for them. The gate holds those two things and
// nothing else. Hologram says which scripts a page requires and what mounting is.
export default class MountGate {
  // Made public to make tests easier
  // The mount waiting for the required scripts, or null when none waits.
  static pendingMount = null;

  // Made public to make tests easier
  static requiredDigests = new Set();

  // Forgets the waiting mount: a script it waits for is never going to load.
  static cancel() {
    $.pendingMount = null;
  }

  // Runs the given mount once every required script is loaded: at once when they are, and
  // otherwise when settle() finds them loaded. A mount still waiting is replaced, since it belongs
  // to a navigation the new one superseded.
  static mountWhenReady(mount) {
    $.pendingMount = mount;
    $.settle();
  }

  // Says which scripts the next mount waits for, in place of the ones required before.
  static require(digests) {
    $.requiredDigests = new Set(digests);
  }

  // Whether the script with the given digest is among the required ones.
  static requires(digest) {
    return $.requiredDigests.has(digest);
  }

  // Runs the waiting mount when every required script is loaded. Called whenever scripts were
  // defined, since any of them can be the last one a mount waits for.
  static settle() {
    if (
      $.pendingMount === null ||
      !ScriptRegistry.isLoaded(Array.from($.requiredDigests))
    ) {
      return;
    }

    const mount = $.pendingMount;
    $.pendingMount = null;

    mount();
  }
}

const $ = MountGate;
