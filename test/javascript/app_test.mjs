"use strict";

import {assert} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";

defineGlobalErlangAndElixirModules();

describe("App", () => {
  describe("loadInstanceId()", () => {
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

      App.loadInstanceId();

      assert.equal(App.instanceId, "abc-123");
    });

    it("overwrites a previously loaded instanceId on subsequent calls", () => {
      globalThis.Hologram = {instanceId: "first"};
      App.loadInstanceId();

      globalThis.Hologram = {instanceId: "second"};
      App.loadInstanceId();

      assert.equal(App.instanceId, "second");
    });
  });
});
