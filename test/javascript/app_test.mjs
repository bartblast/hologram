"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";

defineRuntimeGlobals();

describe("App", () => {
  describe("loadCspNonce()", () => {
    let originalHologram;

    beforeEach(() => {
      originalHologram = globalThis.Hologram;
    });

    afterEach(() => {
      globalThis.Hologram = originalHologram;
      App.cspNonce = null;
    });

    it("reads cspNonce from globalThis.Hologram into App.cspNonce", () => {
      globalThis.Hologram = {cspNonce: "abc123"};

      App.loadCspNonce();

      assert.equal(App.cspNonce, "abc123");
    });

    it("sets App.cspNonce to null when globalThis.Hologram has no cspNonce", () => {
      App.cspNonce = "stale";
      globalThis.Hologram = {};

      App.loadCspNonce();

      assert.isNull(App.cspNonce);
    });
  });

  describe("maybeLoadInstanceId()", () => {
    let originalHologram;

    beforeEach(() => {
      originalHologram = globalThis.Hologram;
      globalThis.Hologram = {};
    });

    afterEach(() => {
      globalThis.Hologram = originalHologram;
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
