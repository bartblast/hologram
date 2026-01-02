"use strict";

import {
  assertBoxedError,
  assertBoxedStrictEqual,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_String from "../../../assets/js/erlang/string.mjs";
import Type from "../../../assets/js/type.mjs";
import Utils from "../../../assets/js/utils.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/ex_js_consistency/erlang/binary_test.exs
// Always update both together.

describe("Erlang_String", () => {
  describe("titlecase/1", () => {
    const titlecase = Erlang_String["titlecase/1"];

    const testType = (inputType, expectedType) => {
      const subject = Utils.shallowCloneObject(inputType);
      let actual = titlecase(subject);
      assertBoxedStrictEqual(actual, expectedType);
      assertBoxedStrictEqual(subject, inputType);
    };

    const testBitstring = (input, expected) => {
      testType(Type.bitstring(input), Type.bitstring(expected));
    };

    it("empty string", () => {
      testBitstring("", "");
    });

    it("capitalizes hologram", () => {
      testBitstring("hologram", "Hologram");
    });

    it("capitalizes hologram once", () => {
      testBitstring("hologram hologram", "Hologram hologram");
    });

    it("raises on int", () => {
      const subject = Type.integer(1);

      assertBoxedError(
        () => titlecase(subject),
        "FunctionClauseError",
        "no function clause matching in :string.titlecase/1\n\nThe following arguments were given to :string.titlecase/1:\n\n    # 1\n    1\n",
      );
    });

    it("emoji", () => {
      [
        ["👩‍👩‍👦‍👦", "👩‍👩‍👦‍👦"],
        ["👩‍🚒", "👩‍🚒"],
      ].forEach(([input, expected]) => {
        testBitstring(input, expected);
      });
    });

    it("empty charlist", () => {
      testType(Type.list([]), Type.list([]));
    });

    it("charlist", () => {
      testType(
        Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
        Type.list([Type.integer(65), Type.integer(98), Type.integer(99)]),
      );
    });

    it("list of charlist", () => {
      testType(
        Type.list([
          Type.list([Type.integer(97)]),
          Type.list([Type.integer(97)]),
        ]),
        Type.list([Type.integer(65), Type.integer(97)]),
      );
    });

    it("list of list of charlist", () => {
      testType(
        Type.list([
          Type.list([
            Type.list([Type.integer(97)]),
            Type.list([Type.integer(97)]),
          ]),
          Type.list([Type.integer(97)]),
        ]),
        Type.list([Type.integer(65), Type.integer(97), Type.integer(97)]),
      );
    });
  });
});
