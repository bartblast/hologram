"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";

defineGlobalErlangAndElixirModules();

describe("App", () => {
  describe("maybeLoadInstanceId()", () => {
    let originalGlobalHologram;

    beforeEach(() => {
      originalGlobalHologram = globalThis.Hologram;
    });

    afterEach(() => {
      if (originalGlobalHologram === undefined) {
        delete globalThis.Hologram;
      } else {
        globalThis.Hologram = originalGlobalHologram;
      }

      App.instanceId = null;
    });

    it("reads instanceId from globalThis.Hologram into App.instanceId", () => {
      globalThis.Hologram = {instanceId: "abc-123"};

      App.maybeLoadInstanceId();

      assert.equal(App.instanceId, "abc-123");
    });

    it("is a no-op when App.instanceId is already set", () => {
      App.instanceId = "stashed-instance";
      globalThis.Hologram = {instanceId: "html-embedded-instance"};

      App.maybeLoadInstanceId();

      assert.equal(App.instanceId, "stashed-instance");
    });
  });
});
