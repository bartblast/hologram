"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Init from "../../../assets/js/erlang/init.mjs";
import MemoryStorage from "../../../assets/js/memory_storage.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/init_test.exs
// Always update both together.

describe("Erlang_Init", () => {
  beforeEach(() => {
    MemoryStorage.data = {};
  });

  describe("get_argument/1", () => {
    const get_argument = Erlang_Init["get_argument/1"];

    it("returns :error when flag is not set", () => {
      const result = get_argument(Type.atom("my_flag"));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("returns {:ok, Arg} when flag is set (single value list)", () => {
      const encodedKey = "tuple(atom(init_argument),atom(my_flag))";
      const value = Type.list([Type.list([Type.bitstring("value1")])]);
      MemoryStorage.put(encodedKey, value);

      const result = get_argument(Type.atom("my_flag"));
      const expected = Type.tuple([Type.atom("ok"), value]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns {:ok, Arg} when flag is set multiple times", () => {
      const encodedKey = "tuple(atom(init_argument),atom(my_flag))";
      const value = Type.list([
        Type.list([Type.bitstring("value1"), Type.bitstring("value2")]),
        Type.list([Type.bitstring("value3")]),
      ]);
      MemoryStorage.put(encodedKey, value);

      const result = get_argument(Type.atom("my_flag"));
      const expected = Type.tuple([Type.atom("ok"), value]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns {:ok, Arg} for system flag :root (when configured)", () => {
      const encodedKey = "tuple(atom(init_argument),atom(root))";
      const value = Type.list([Type.list([Type.bitstring("/usr/local/otp")])]);
      MemoryStorage.put(encodedKey, value);

      const result = get_argument(Type.atom("root"));
      const expected = Type.tuple([Type.atom("ok"), value]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns {:ok, Arg} for system flag :home (when configured)", () => {
      const encodedKey = "tuple(atom(init_argument),atom(home))";
      const value = Type.list([Type.list([Type.bitstring("/home/user")])]);
      MemoryStorage.put(encodedKey, value);

      const result = get_argument(Type.atom("home"));
      const expected = Type.tuple([Type.atom("ok"), value]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns {:ok, Arg} for system flag :progname (when configured)", () => {
      const encodedKey = "tuple(atom(init_argument),atom(progname))";
      const value = Type.list([Type.list([Type.bitstring("erl")])]);
      MemoryStorage.put(encodedKey, value);

      const result = get_argument(Type.atom("progname"));
      const expected = Type.tuple([Type.atom("ok"), value]);

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error for nil", () => {
      const result = get_argument(Type.atom("nil"));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error if the argument is not an atom (integer)", () => {
      const result = get_argument(Type.integer(1));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error if the argument is not an atom (binary)", () => {
      const result = get_argument(Type.bitstring("my_flag"));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("returns :error if the argument is not an atom (list)", () => {
      const result = get_argument(
        Type.list([Type.integer(1), Type.integer(2)]),
      );
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });
  });
});
