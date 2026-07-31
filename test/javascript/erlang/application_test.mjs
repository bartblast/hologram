"use strict";

import {
  assert,
  assertBoxedError,
  buildFunctionClauseErrorMsg,
  defineRuntimeGlobals,
} from "../support/helpers.mjs";

import Erlang_Application from "../../../assets/js/erlang/application.mjs";
import ERTS from "../../../assets/js/erts.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineRuntimeGlobals();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/application_test.exs
// Always update both together.

describe("Erlang_Application", () => {
  describe("get_application/1", () => {
    const get_application = Erlang_Application["get_application/1"];

    before(() => {
      Interpreter.defineElixirFunction(
        "MyModuleWithMetadata",
        "my_fun",
        0,
        "public",
        [],
        {app: "my_app", file: "lib/my_module.ex", vsn: "1.2.3"},
      );

      Interpreter.defineElixirFunction(
        "MyModuleWithoutMetadata",
        "my_fun",
        0,
        "public",
        [],
      );
    });

    it("module belonging to an application", () => {
      const result = get_application(Type.alias("MyModuleWithMetadata"));

      const expected = Type.tuple([Type.atom("ok"), Type.atom("my_app")]);

      assert.deepStrictEqual(result, expected);
    });

    it("module carrying no metadata", () => {
      const result = get_application(Type.alias("MyModuleWithoutMetadata"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });

    it("module that isn't in the bundle", () => {
      const result = get_application(Type.alias("NoSuchModule"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });

    it("raises FunctionClauseError if the argument is not an atom", () => {
      assertBoxedError(
        () => get_application(Type.integer(123)),
        "FunctionClauseError",
        buildFunctionClauseErrorMsg(":application.get_application/1", [
          Type.integer(123),
        ]),
      );
    });
  });

  describe("get_key/2", () => {
    const get_key = Erlang_Application["get_key/2"];

    before(() => {
      ERTS.appVersions = {my_app: "1.2.3"};
    });

    after(() => {
      ERTS.appVersions = {};
    });

    it("vsn of a known application", () => {
      const result = get_key(Type.atom("my_app"), Type.atom("vsn"));

      const expected = Type.tuple([Type.atom("ok"), Type.charlist("1.2.3")]);

      assert.deepStrictEqual(result, expected);
    });

    it("vsn of an unknown application", () => {
      const result = get_key(Type.atom("no_such_app"), Type.atom("vsn"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });

    // The client carries each application's version and nothing else of its
    // specification, so every other key is undefined - which is what the BEAM
    // answers for a key an application doesn't define.
    it("key other than vsn", () => {
      const result = get_key(Type.atom("my_app"), Type.atom("description"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });

    it("application that is not an atom", () => {
      const result = get_key(Type.bitstring("my_app"), Type.atom("vsn"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });

    it("key that is not an atom", () => {
      const result = get_key(Type.atom("my_app"), Type.bitstring("vsn"));

      assert.deepStrictEqual(result, Type.atom("undefined"));
    });
  });
});
