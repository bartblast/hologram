"use strict";

import HologramRuntimeError from "./errors/runtime_error.mjs";

// The script files the document runs besides the runtime, page bundles and chunks alike, each
// named by the digest of its content and each with a status: "requested" once the document holds
// a script element for it, "loaded" once its functions are defined, "failed" when it could not be
// fetched.
//
// A script does not define its functions when it runs: it leaves them in
// globalThis.Hologram.pendingScripts with its digest and dispatches hologram:scriptLoaded, since it
// can run before the runtime does. The registry defines them when it is asked to.
//
// The registry holds the statuses and nothing else. It knows no page, no epoch and no action:
// Hologram decides what waits for which script.
export default class ScriptRegistry {
  // Made public to make tests easier
  static statuses = new Map();

  // Defines the functions of every script that ran since the last call, with the given deps, and
  // marks those scripts loaded. Returns their digests, in the order the scripts ran.
  static defineLoaded(deps) {
    const pendingScripts = globalThis.Hologram.pendingScripts ?? [];
    globalThis.Hologram.pendingScripts = [];

    return pendingScripts.map(({define, digest}) => {
      define(deps);
      $.statuses.set(digest, "loaded");

      return digest;
    });
  }

  // Whether any of the scripts with the given digests could not be fetched.
  static hasFailed(digests) {
    return digests.some((digest) => $.statuses.get(digest) === "failed");
  }

  // Whether every script with the given digests has its functions defined.
  static isLoaded(digests) {
    return digests.every((digest) => $.statuses.get(digest) === "loaded");
  }

  // Marks the scripts with the given digests requested, unless they have a status already. For the
  // scripts the document carries as script elements from the start.
  static markRequested(digests) {
    for (const digest of digests) {
      if (!$.statuses.has(digest)) {
        $.statuses.set(digest, "requested");
      }
    }
  }

  // Fetches the given scripts, each given as {digest, path}, unless they have a status already.
  //
  // Without the failure path a script that never loads would leave whatever waits for it waiting
  // in silence: the hologram:scriptFailed event, which carries the digest, is what lets the page
  // stop waiting.
  //
  // Throwing from the handler does not reach whoever asked for the script, since the handler runs
  // off the event loop. It surfaces as an uncaught error instead, which is what the console and
  // the feature tests read.
  //
  // A failed script is not fetched again: its status stays, so a later request passes it over.
  static request(scripts) {
    for (const {digest, path} of scripts) {
      if ($.statuses.has(digest)) {
        continue;
      }

      $.statuses.set(digest, "requested");

      const script = document.createElement("script");

      script.src = path;
      script.async = true;
      script.fetchPriority = "high";

      script.onerror = () => {
        $.statuses.set(digest, "failed");

        document.dispatchEvent(
          new CustomEvent("hologram:scriptFailed", {detail: {digest: digest}}),
        );

        throw new HologramRuntimeError(`Failed to load script: ${path}`);
      };

      document.head.appendChild(script);
    }
  }
}

const $ = ScriptRegistry;
