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
// The registry holds the statuses and the promises waiting for them (see whenLoaded), and nothing
// else. It knows no page, no epoch and no action: Hologram decides what waits for which script.
export default class ScriptRegistry {
  // Made public to make tests easier
  static statuses = new Map();

  // Made public to make tests easier
  // The promises still waiting for scripts, each with the digests it waits for.
  static waiters = [];

  // Defines the functions of every script that ran since the last call, with the given deps, and
  // marks those scripts loaded. Returns their digests, in the order the scripts ran.
  static defineLoaded(deps) {
    const pendingScripts = globalThis.Hologram.pendingScripts ?? [];
    globalThis.Hologram.pendingScripts = [];

    const digests = pendingScripts.map(({define, digest}) => {
      define(deps);
      $.statuses.set(digest, "loaded");

      return digest;
    });

    $.#resolveWaiters();

    return digests;
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

  // Fetches the given scripts, each given as {digest, path}, unless they are requested or loaded
  // already. A script that failed is fetched again: a new need for it is a new attempt.
  //
  // Without the failure path a script that never loads would leave whatever waits for it waiting
  // in silence: the given function, called with the digest, is what lets the caller stop waiting.
  //
  // Throwing from the handler does not reach whoever asked for the script, since the handler runs
  // off the event loop. It surfaces as an uncaught error instead, which is what the console and
  // the feature tests read.
  static request(scripts, onFailure) {
    for (const {digest, path} of scripts) {
      const status = $.statuses.get(digest);

      if (status === "requested" || status === "loaded") {
        continue;
      }

      $.statuses.set(digest, "requested");

      const script = document.createElement("script");

      script.src = path;
      script.async = true;
      script.fetchPriority = "high";

      script.onerror = () => {
        $.statuses.set(digest, "failed");
        $.#rejectWaiters(digest);
        onFailure(digest);

        throw new HologramRuntimeError(`Failed to load script: ${path}`);
      };

      document.head.appendChild(script);
    }
  }

  // Returns a promise that resolves once every script with the given digests is loaded, and
  // rejects with the digest of the first of them that fails to load. It is settled already when
  // the scripts are loaded, or when one of them has failed and was not requested again.
  static whenLoaded(digests) {
    if ($.isLoaded(digests)) {
      return Promise.resolve();
    }

    const failedDigest = digests.find(
      (digest) => $.statuses.get(digest) === "failed",
    );

    if (failedDigest !== undefined) {
      return Promise.reject(failedDigest);
    }

    return new Promise((resolve, reject) => {
      $.waiters.push({digests: digests, reject: reject, resolve: resolve});
    });
  }

  // Rejects the promises waiting for the script with the given digest, and forgets them.
  static #rejectWaiters(digest) {
    const [rejectedWaiters, otherWaiters] = $.#splitWaiters((waiter) =>
      waiter.digests.includes(digest),
    );

    $.waiters = otherWaiters;
    rejectedWaiters.forEach((waiter) => waiter.reject(digest));
  }

  // Resolves the promises whose scripts are all loaded, and forgets them.
  static #resolveWaiters() {
    const [resolvedWaiters, otherWaiters] = $.#splitWaiters((waiter) =>
      $.isLoaded(waiter.digests),
    );

    $.waiters = otherWaiters;
    resolvedWaiters.forEach((waiter) => waiter.resolve());
  }

  // The waiters the given function holds for, and the rest.
  static #splitWaiters(predicate) {
    return [
      $.waiters.filter((waiter) => predicate(waiter)),
      $.waiters.filter((waiter) => !predicate(waiter)),
    ];
  }
}

const $ = ScriptRegistry;
