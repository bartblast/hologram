"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import ERTS from "../../assets/js/erts.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("ERTS", () => {
  describe("registerPromise()", () => {
    it("returns a Task struct with correct fields", () => {
      const promise = Promise.resolve(42);
      const task = ERTS.registerPromise(promise);

      const mfa = Type.tuple([
        Type.alias("Hologram.JS"),
        Type.atom("call"),
        Type.integer(3),
      ]);

      const refKey = Type.encodeMapKey(Type.atom("ref"));
      const ref = task.data[refKey][1];

      const expected = Type.taskStruct(mfa, ERTS.INIT_PID, ref);

      assert.deepStrictEqual(task, expected);
    });

    it("returns unique Task structs for different promises", () => {
      const task1 = ERTS.registerPromise(Promise.resolve(1));
      const task2 = ERTS.registerPromise(Promise.resolve(2));

      const refKey = Type.encodeMapKey(Type.atom("ref"));
      const ref1 = task1.data[refKey][1];
      const ref2 = task2.data[refKey][1];

      assert.isFalse(Interpreter.isEqual(ref1, ref2));
    });
  });

  describe("takePromise()", () => {
    it("returns the stored Promise for a registered Task struct", () => {
      const promise = Promise.resolve(42);
      const task = ERTS.registerPromise(promise);

      assert.strictEqual(ERTS.takePromise(task), promise);
    });

    it("removes the Promise from the registry after taking", () => {
      const promise = Promise.resolve(42);
      const task = ERTS.registerPromise(promise);

      ERTS.takePromise(task);

      assert.isNull(ERTS.takePromise(task));
    });

    it("returns null when the ref is not in the registry", () => {
      const ref = ERTS.uniqueReference();
      const task = Type.taskStruct("dummy_mfa", "dummy_owner", ref);

      assert.isNull(ERTS.takePromise(task));
    });
  });

  describe("uniqueReference()", () => {
    it("returns a reference", () => {
      const result = ERTS.uniqueReference();

      assert.isTrue(Type.isReference(result));
    });

    it("uses the client node", () => {
      const result = ERTS.uniqueReference();

      assert.strictEqual(result.node, ERTS.nodeTable.CLIENT_NODE);
    });

    it("consecutive calls return unique references", () => {
      const ref1 = ERTS.uniqueReference();
      const ref2 = ERTS.uniqueReference();

      assert.isFalse(Interpreter.isEqual(ref1, ref2));
    });
  });
});
