"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import HologramBoxedError from "../../../assets/js/errors/boxed_error.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("HologramBoxedError", () => {
  describe("error kind (default)", () => {
    it("defaults the kind to :error", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.kind, Type.atom("error"));
    });

    it("sets value and struct to the given exception struct", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.deepStrictEqual(error.value, struct);
      assert.deepStrictEqual(error.struct, struct);
    });

    it("renders the message from the exception type and message", () => {
      const struct = Type.errorStruct("MyType", "my message");
      const error = new HologramBoxedError(struct);

      assert.equal(error.message, "(MyType) my message");
    });

    it("can throw and catch", () => {
      const struct = Type.errorStruct("MyType", "my message");

      try {
        throw new HologramBoxedError(struct);
      } catch (error) {
        assert.instanceOf(error, HologramBoxedError);
        assert.deepStrictEqual(error.struct, struct);
      }
    });
  });

  describe("throw kind", () => {
    it("sets kind and value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("throw"));

      assert.deepStrictEqual(error.kind, Type.atom("throw"));
      assert.deepStrictEqual(error.value, value);
    });

    it("renders the message from the inspected value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("throw"));

      assert.equal(error.message, "(throw) 42");
    });
  });

  describe("exit kind", () => {
    it("sets kind and value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("exit"));

      assert.deepStrictEqual(error.kind, Type.atom("exit"));
      assert.deepStrictEqual(error.value, value);
    });

    it("renders the message from the inspected value", () => {
      const value = Type.integer(42);
      const error = new HologramBoxedError(value, Type.atom("exit"));

      assert.equal(error.message, "(exit) 42");
    });
  });
});
