"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import TrustedTypes from "../../assets/js/trusted_types.mjs";

defineRuntimeGlobals();

describe("TrustedTypes", () => {
  let createdPolicies;

  // A browser's trustedTypes, recording the policies created, whose values wrap their input so a
  // test can tell them from plain strings.
  const stubTrustedTypes = () => {
    createdPolicies = [];

    globalThis.trustedTypes = {
      createPolicy: (name, rules) => {
        createdPolicies.push(name);

        return {
          createScript: (code) => ({trustedScript: rules.createScript(code)}),
          createScriptURL: (url) => ({
            trustedScriptURL: rules.createScriptURL(url),
          }),
        };
      },
    };
  };

  beforeEach(() => {
    TrustedTypes.cachedPolicy = undefined;
  });

  afterEach(() => {
    delete globalThis.trustedTypes;
    TrustedTypes.cachedPolicy = undefined;
  });

  describe("policy()", () => {
    it("creates the policy named hologram once", () => {
      stubTrustedTypes();

      const policy = TrustedTypes.policy();

      assert.strictEqual(TrustedTypes.policy(), policy);
      assert.deepStrictEqual(createdPolicies, ["hologram"]);
    });

    it("is null when the browser has no Trusted Types", () => {
      assert.isNull(TrustedTypes.policy());
    });

    // A trusted-types directive not listing "hologram" can reach the page through a meta tag or a
    // proxy, and the browser then refuses to create the policy.
    it("is null when the browser refuses the policy", () => {
      globalThis.trustedTypes = {
        createPolicy: () => {
          throw new TypeError("Policy hologram disallowed.");
        },
      };

      assert.isNull(TrustedTypes.policy());
      assert.equal(TrustedTypes.script("go();"), "go();");
    });
  });

  describe("script()", () => {
    it("the policy's value for the code, which it passes through", () => {
      stubTrustedTypes();

      assert.deepStrictEqual(TrustedTypes.script("go();"), {
        trustedScript: "go();",
      });
    });

    it("the plain code when the browser has no Trusted Types", () => {
      assert.equal(TrustedTypes.script("go();"), "go();");
    });
  });

  describe("scriptUrl()", () => {
    it("the policy's value for the URL, which it passes through", () => {
      stubTrustedTypes();

      assert.deepStrictEqual(TrustedTypes.scriptUrl("/app.js"), {
        trustedScriptURL: "/app.js",
      });
    });

    it("the plain URL when the browser has no Trusted Types", () => {
      assert.equal(TrustedTypes.scriptUrl("/app.js"), "/app.js");
    });
  });
});
