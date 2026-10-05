"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import MountGate from "../../assets/js/mount_gate.mjs";
import ScriptRegistry from "../../assets/js/script_registry.mjs";

defineRuntimeGlobals();

describe("MountGate", () => {
  const reset = () => {
    MountGate.pendingMount = null;
    MountGate.requiredDigests = new Set();
    ScriptRegistry.statuses.clear();
  };

  beforeEach(() => reset());

  afterEach(() => reset());

  describe("cancel()", () => {
    it("forgets the waiting mount", () => {
      const mount = sinon.spy();

      MountGate.require(["AAAAAAAA"]);
      MountGate.mountWhenReady(mount);

      MountGate.cancel();

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      MountGate.settle();

      assert.isNull(MountGate.pendingMount);
      sinon.assert.notCalled(mount);
    });
  });

  describe("mountWhenReady()", () => {
    it("mounts at once when no script is required", () => {
      const mount = sinon.spy();

      MountGate.mountWhenReady(mount);

      sinon.assert.calledOnce(mount);
      assert.isNull(MountGate.pendingMount);
    });

    it("mounts at once when every required script is loaded", () => {
      const mount = sinon.spy();

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "loaded");
      MountGate.require(["AAAAAAAA", "BBBBBBBB"]);

      MountGate.mountWhenReady(mount);

      sinon.assert.calledOnce(mount);
      assert.isNull(MountGate.pendingMount);
    });

    it("replaces a mount still waiting", () => {
      const supersededMount = sinon.spy();
      const mount = sinon.spy();

      MountGate.require(["AAAAAAAA"]);
      MountGate.mountWhenReady(supersededMount);
      MountGate.mountWhenReady(mount);

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      MountGate.settle();

      sinon.assert.notCalled(supersededMount);
      sinon.assert.calledOnce(mount);
    });

    it("waits while a required script is not loaded", () => {
      const mount = sinon.spy();

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "requested");
      MountGate.require(["AAAAAAAA", "BBBBBBBB"]);

      MountGate.mountWhenReady(mount);

      sinon.assert.notCalled(mount);
      assert.strictEqual(MountGate.pendingMount, mount);
    });
  });

  describe("require()", () => {
    it("replaces the scripts required before", () => {
      MountGate.require(["AAAAAAAA", "BBBBBBBB"]);
      MountGate.require(["CCCCCCCC"]);

      assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
        "CCCCCCCC",
      ]);
    });

    it("requires each script once", () => {
      MountGate.require(["AAAAAAAA", "AAAAAAAA"]);

      assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
        "AAAAAAAA",
      ]);
    });
  });

  describe("requires()", () => {
    beforeEach(() => MountGate.require(["AAAAAAAA"]));

    it("a required script", () => {
      assert.isTrue(MountGate.requires("AAAAAAAA"));
    });

    it("a script that is not required", () => {
      assert.isFalse(MountGate.requires("BBBBBBBB"));
    });
  });

  describe("settle()", () => {
    it("does nothing when no mount waits", () => {
      MountGate.settle();

      assert.isNull(MountGate.pendingMount);
    });

    it("keeps the mount waiting while a required script is not loaded", () => {
      const mount = sinon.spy();

      MountGate.require(["AAAAAAAA", "BBBBBBBB"]);
      MountGate.mountWhenReady(mount);

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      MountGate.settle();

      sinon.assert.notCalled(mount);
      assert.strictEqual(MountGate.pendingMount, mount);
    });

    it("runs the waiting mount once, when the last required script is loaded", () => {
      const mount = sinon.spy();

      MountGate.require(["AAAAAAAA", "BBBBBBBB"]);
      MountGate.mountWhenReady(mount);

      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");
      ScriptRegistry.statuses.set("BBBBBBBB", "loaded");
      MountGate.settle();
      MountGate.settle();

      sinon.assert.calledOnce(mount);
      assert.isNull(MountGate.pendingMount);
    });

    // The mount is forgotten before it runs, so a mount that asks the gate again finds it empty.
    it("leaves no mount waiting while the mount runs", () => {
      let pendingMountDuringMount;

      MountGate.mountWhenReady(() => {
        pendingMountDuringMount = MountGate.pendingMount;
      });

      assert.isNull(pendingMountDuringMount);
    });
  });
});
