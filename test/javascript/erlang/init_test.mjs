"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Init from "../../../assets/js/erlang/init.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/init_test.exs
// Always update both together.

describe("Erlang_Init", () => {
  describe("get_argument/1", () => {
    const get_argument = Erlang_Init["get_argument/1"];

    it(":home flag", () => {
      const result = get_argument(Type.atom("home"));

      const expected = Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("/")])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it(":progname flag", () => {
      const result = get_argument(Type.atom("progname"));

      const expected = Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("hologram")])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it(":root flag", () => {
      const result = get_argument(Type.atom("root"));

      const expected = Type.tuple([
        Type.atom("ok"),
        Type.list([Type.list([Type.charlist("/")])]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("unknown flag", () => {
      const result = get_argument(Type.atom("my_nonexistent_flag"));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("argument is nil", () => {
      const result = get_argument(Type.atom("nil"));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });

    it("argument is not an atom", () => {
      const result = get_argument(Type.integer(1));
      const expected = Type.atom("error");

      assert.deepStrictEqual(result, expected);
    });
  });
});
