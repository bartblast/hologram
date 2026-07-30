"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import ERTS from "../../assets/js/erts.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("ERTS", () => {
  describe("formatErrorMap()", () => {
    const expandError = (fragment) => Type.bitstring(`expanded ${fragment}`);

    it("names the argument positions the fragments describe", () => {
      const result = ERTS.formatErrorMap(
        ["not_atom", "not_list"],
        1,
        Type.map(),
        expandError,
      );

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.integer(1), Type.bitstring("expanded not_atom")],
          [Type.integer(2), Type.bitstring("expanded not_list")],
        ]),
      );
    });

    it("counts the argument positions from the given number", () => {
      const result = ERTS.formatErrorMap(
        ["not_atom"],
        3,
        Type.map(),
        expandError,
      );

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(3), Type.bitstring("expanded not_atom")]]),
      );
    });

    it("leaves the position of an empty fragment unnamed", () => {
      const result = ERTS.formatErrorMap(
        ["", "not_list"],
        1,
        Type.map(),
        expandError,
      );

      assert.deepStrictEqual(
        result,
        Type.map([[Type.integer(2), Type.bitstring("expanded not_list")]]),
      );
    });

    it("names the call as a whole for a general fragment", () => {
      const result = ERTS.formatErrorMap(
        [{general: "bad_options"}, "not_list"],
        1,
        Type.map(),
        expandError,
      );

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("general"), Type.bitstring("expanded bad_options")],
          [Type.integer(1), Type.bitstring("expanded not_list")],
        ]),
      );
    });

    it("keeps the entries the given map already holds", () => {
      const map = Type.map([[Type.atom("reason"), Type.bitstring("boom")]]);

      const result = ERTS.formatErrorMap(["not_atom"], 1, map, expandError);

      assert.deepStrictEqual(
        result,
        Type.map([
          [Type.atom("reason"), Type.bitstring("boom")],
          [Type.integer(1), Type.bitstring("expanded not_atom")],
        ]),
      );
    });

    it("leaves the given map untouched", () => {
      const map = Type.map();

      ERTS.formatErrorMap(["not_atom"], 1, map, expandError);

      assert.deepStrictEqual(map, Type.map());
    });
  });

  describe("registerNativeObject()", () => {
    it("returns a reference", () => {
      const obj = {a: 1};
      const ref = ERTS.registerNativeObject(obj);

      assert.isTrue(Type.isReference(ref));
    });

    it("stores the object in the NativeObjectRegistry", () => {
      const obj = {a: 1};
      const ref = ERTS.registerNativeObject(obj);

      assert.strictEqual(ERTS.nativeObjectRegistry.get(ref), obj);
    });

    it("returns unique references for different objects", () => {
      const ref1 = ERTS.registerNativeObject({a: 1});
      const ref2 = ERTS.registerNativeObject({b: 2});

      assert.isFalse(Interpreter.isEqual(ref1, ref2));
    });
  });

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
