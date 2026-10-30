"use strict";

// The values the runtime assigns to the script sinks Trusted Types guards: a script's code and a
// script's URL. A document whose policy enforces Trusted Types refuses a plain string at such a
// sink, so the runtime assigns them through a policy of its own, named "hologram", which a
// trusted-types directive the app gives allows (see Hologram.Runtime.ContentSecurityPolicy).
//
// The policy passes its input through. Every input is the framework's own: a chunk's URL, built
// from its digest, the code of a template's script element, and the code of a JS.exec or JS.eval
// call, which comes from the developer's source.
//
// A browser without Trusted Types takes the plain values.
export default class TrustedTypes {
  // The policy once created, null when there is none to be had, undefined before the first ask. A
  // document can create a policy of a given name only once.
  //
  // Made public to make tests easier
  static cachedPolicy = undefined;

  // Null when the browser has no Trusted Types, or refuses the policy: a trusted-types directive
  // that does not list "hologram" can reach a page past Hologram's config, through a meta tag or a
  // proxy. A page that does not enforce Trusted Types then works on the plain values, and one that
  // does refuses them at the sink, where the runtime reports what was refused.
  static policy() {
    if ($.cachedPolicy === undefined) {
      try {
        $.cachedPolicy =
          globalThis.trustedTypes?.createPolicy("hologram", {
            createScript: (code) => code,
            createScriptURL: (url) => url,
          }) ?? null;
      } catch {
        $.cachedPolicy = null;
      }
    }

    return $.cachedPolicy;
  }

  static script(code) {
    const policy = $.policy();
    return policy === null ? code : policy.createScript(code);
  }

  static scriptUrl(url) {
    const policy = $.policy();
    return policy === null ? url : policy.createScriptURL(url);
  }
}

const $ = TrustedTypes;
