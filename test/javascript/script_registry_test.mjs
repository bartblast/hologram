"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import ScriptRegistry from "../../assets/js/script_registry.mjs";

defineRuntimeGlobals();

describe("ScriptRegistry", () => {
  const deps = {dep: "dep"};

  const requestedScripts = () =>
    Array.from(document.head.querySelectorAll("script[src^='/hologram/']"));

  beforeEach(() => {
    ScriptRegistry.statuses.clear();
    delete globalThis.Hologram.pendingScripts;
  });

  afterEach(() => {
    ScriptRegistry.statuses.clear();
    delete globalThis.Hologram.pendingScripts;
    requestedScripts().forEach((script) => script.remove());
  });

  describe("defineLoaded()", () => {
    it("calls each script's define with the deps, in the order the scripts ran", () => {
      const calls = [];

      globalThis.Hologram.pendingScripts = [
        {define: (arg) => calls.push(["AAAAAAAA", arg]), digest: "AAAAAAAA"},
        {define: (arg) => calls.push(["BBBBBBBB", arg]), digest: "BBBBBBBB"},
      ];

      ScriptRegistry.defineLoaded(deps);

      assert.deepStrictEqual(calls, [
        ["AAAAAAAA", deps],
        ["BBBBBBBB", deps],
      ]);
    });

    it("leaves no script pending", () => {
      globalThis.Hologram.pendingScripts = [
        {define: () => null, digest: "AAAAAAAA"},
      ];

      ScriptRegistry.defineLoaded(deps);

      assert.deepStrictEqual(globalThis.Hologram.pendingScripts, []);
    });

    it("marks the scripts loaded", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "requested");

      globalThis.Hologram.pendingScripts = [
        {define: () => null, digest: "AAAAAAAA"},
        {define: () => null, digest: "BBBBBBBB"},
      ];

      ScriptRegistry.defineLoaded(deps);

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "loaded"],
        ["BBBBBBBB", "loaded"],
      ]);
    });

    it("returns no digest when no script ran", () => {
      assert.deepStrictEqual(ScriptRegistry.defineLoaded(deps), []);
      assert.deepStrictEqual(globalThis.Hologram.pendingScripts, []);
    });

    it("returns the digests of the scripts, in the order the scripts ran", () => {
      globalThis.Hologram.pendingScripts = [
        {define: () => null, digest: "BBBBBBBB"},
        {define: () => null, digest: "AAAAAAAA"},
      ];

      assert.deepStrictEqual(ScriptRegistry.defineLoaded(deps), [
        "BBBBBBBB",
        "AAAAAAAA",
      ]);
    });
  });

  describe("hasFailed()", () => {
    beforeEach(() => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "requested");
      ScriptRegistry.statuses.set("CCCCCCCC", "failed");
    });

    it("a failed script among the given ones", () => {
      assert.isTrue(ScriptRegistry.hasFailed(["AAAAAAAA", "CCCCCCCC"]));
    });

    it("no failed script among the given ones", () => {
      assert.isFalse(
        ScriptRegistry.hasFailed(["AAAAAAAA", "BBBBBBBB", "DDDDDDDD"]),
      );
    });

    it("no script given", () => {
      assert.isFalse(ScriptRegistry.hasFailed([]));
    });
  });

  describe("isLoaded()", () => {
    beforeEach(() => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "loaded");
      ScriptRegistry.statuses.set("CCCCCCCC", "requested");
      ScriptRegistry.statuses.set("DDDDDDDD", "failed");
    });

    it("a failed script among the given ones", () => {
      assert.isFalse(ScriptRegistry.isLoaded(["AAAAAAAA", "DDDDDDDD"]));
    });

    it("a requested script among the given ones", () => {
      assert.isFalse(ScriptRegistry.isLoaded(["AAAAAAAA", "CCCCCCCC"]));
    });

    it("a script with no status among the given ones", () => {
      assert.isFalse(ScriptRegistry.isLoaded(["AAAAAAAA", "EEEEEEEE"]));
    });

    it("every given script loaded", () => {
      assert.isTrue(ScriptRegistry.isLoaded(["AAAAAAAA", "BBBBBBBB"]));
    });

    it("no script given", () => {
      assert.isTrue(ScriptRegistry.isLoaded([]));
    });
  });

  describe("markRequested()", () => {
    it("leaves a script that has a status as it is", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "failed");

      ScriptRegistry.markRequested(["AAAAAAAA", "BBBBBBBB"]);

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "loaded"],
        ["BBBBBBBB", "failed"],
      ]);
    });

    it("marks a script with no status requested", () => {
      ScriptRegistry.markRequested(["AAAAAAAA", "BBBBBBBB"]);

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "requested"],
        ["BBBBBBBB", "requested"],
      ]);
    });
  });

  describe("request()", () => {
    const scriptA = {digest: "AAAAAAAA", path: "/hologram/chunk-AAAAAAAA.js"};
    const scriptB = {digest: "BBBBBBBB", path: "/hologram/chunk-BBBBBBBB.js"};

    it("appends a script element for each script with no status", () => {
      ScriptRegistry.request([scriptA, scriptB], () => null);

      const scripts = requestedScripts();

      assert.deepStrictEqual(
        scripts.map((script) => script.getAttribute("src")),
        ["/hologram/chunk-AAAAAAAA.js", "/hologram/chunk-BBBBBBBB.js"],
      );

      assert.isTrue(scripts.every((script) => script.async === true));
      assert.isTrue(scripts.every((script) => script.fetchPriority === "high"));
    });

    it("fetches a script that failed again", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "failed");

      ScriptRegistry.request([scriptA], () => null);

      assert.deepStrictEqual(
        requestedScripts().map((script) => script.getAttribute("src")),
        ["/hologram/chunk-AAAAAAAA.js"],
      );

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "requested"],
      ]);
    });

    it("marks each script requested", () => {
      ScriptRegistry.request([scriptA, scriptB], () => null);

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "requested"],
        ["BBBBBBBB", "requested"],
      ]);
    });

    it("passes over a script that is loaded or requested", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "requested");

      ScriptRegistry.request([scriptA, scriptB], () => null);

      assert.deepStrictEqual(requestedScripts(), []);

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "loaded"],
        ["BBBBBBBB", "requested"],
      ]);
    });

    it("a script that fails to load is marked failed, reported to the caller and raised", () => {
      const onFailure = sinon.spy();

      ScriptRegistry.request([scriptA, scriptB], onFailure);

      const [script] = requestedScripts();

      assert.throws(
        () => script.onerror(),
        HologramRuntimeError,
        "Failed to load script: /hologram/chunk-AAAAAAAA.js",
      );

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "failed"],
        ["BBBBBBBB", "requested"],
      ]);

      sinon.assert.calledOnceWithExactly(onFailure, "AAAAAAAA");
    });
  });
});
