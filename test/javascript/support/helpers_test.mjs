"use strict";

import {
  assert,
  assertBoxedError,
  buildArgumentErrorMsg,
  buildBadFunctionErrorMsg,
  buildErlangErrorMsg,
  buildFunctionClauseErrorMsg,
  buildKeyErrorMsg,
  buildMatchErrorMsg,
  buildMultiArgumentErrorMsg,
  buildTryClauseErrorMsg,
  buildUndefinedFunctionErrorMsg,
  defineRuntimeGlobals,
} from "./helpers.mjs";

import Type from "../../../assets/js/type.mjs";

import {defineModule1Fixture} from "./fixtures/router/helpers/module_1.mjs";
import {defineModule2Fixture} from "./fixtures/router/helpers/module_2.mjs";

defineRuntimeGlobals();

defineModule1Fixture();
defineModule2Fixture();

const module1 = Type.alias("Hologram.Test.Fixtures.Router.Helpers.Module1");
const module2 = Type.alias("Hologram.Test.Fixtures.Router.Helpers.Module2");

describe("defineElixirHologramRouterHelpersModule", () => {
  describe("page_path/1", () => {
    const page_path = Elixir_Hologram_Router_Helpers["page_path/1"];

    it("module arg", () => {
      const result = page_path(module1);

      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module1",
      );

      assert.deepStrictEqual(result, expected);
    });

    it("tuple arg", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
      ]);

      const result = page_path(Type.tuple([module2, params]));

      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module2/abc/123",
      );

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("page_path/2", () => {
    const page_path = Elixir_Hologram_Router_Helpers["page_path/2"];

    it("valid params", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
      ]);

      const result = page_path(module2, params);

      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module2/abc/123",
      );

      assert.deepStrictEqual(result, expected);
    });

    it("missing single param", () => {
      assertBoxedError(
        () =>
          page_path(
            module2,
            Type.keywordList([[Type.atom("param_2"), Type.integer(123)]]),
          ),
        "ArgumentError",
        'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
      );
    });

    it("missing multiple params", () => {
      assertBoxedError(
        () => page_path(module2, Type.keywordList()),
        "ArgumentError",
        'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
      );
    });

    it("extraneous single param", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
        [Type.atom("param_3"), Type.bitstring("xyz")],
      ]);

      assertBoxedError(
        () => page_path(module2, params),
        "ArgumentError",
        `page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param`,
      );
    });

    it("extraneous multiple params", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
        [Type.atom("param_3"), Type.bitstring("xyz")],
        [Type.atom("param_4"), Type.integer(987)],
      ]);

      assertBoxedError(
        () => page_path(module2, params),
        "ArgumentError",
        `page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param`,
      );
    });
  });
});

it("buildArgumentErrorMsg()", () => {
  const result = buildArgumentErrorMsg(2, "my message");

  const expected =
    "errors were found at the given arguments:\n\n  * 2nd argument: my message\n";

  assert.equal(result, expected);
});

it("buildBadFunctionErrorMsg()", () => {
  const term = Type.map([
    [Type.atom("a"), Type.integer(1)],
    [Type.atom("b"), Type.integer(2)],
  ]);

  const result = buildBadFunctionErrorMsg(term);
  const expected = "expected a function, got: %{a: 1, b: 2}";

  assert.equal(result, expected);
});

it("buildErlangErrorMsg()", () => {
  const result = buildErlangErrorMsg("my message");

  assert.equal(result, "Erlang error: my message");
});

describe("buildFunctionClauseErrorMsg()", () => {
  it("no args param given", () => {
    const result = buildFunctionClauseErrorMsg("MyModule.my_fun/2");

    const expected = "no function clause matching in MyModule.my_fun/2";

    assert.equal(result, expected);
  });

  it("0 args", () => {
    const result = buildFunctionClauseErrorMsg("MyModule.my_fun/2", []);

    const expected = "no function clause matching in MyModule.my_fun/2";

    assert.equal(result, expected);
  });

  it("1 arg", () => {
    const result = buildFunctionClauseErrorMsg("MyModule.my_fun/2", [
      Type.integer(123),
    ]);

    const expected =
      "no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    123\n";

    assert.equal(result, expected);
  });

  it("2 args", () => {
    const result = buildFunctionClauseErrorMsg("MyModule.my_fun/2", [
      Type.integer(123),
      Type.atom("abc"),
    ]);

    const expected =
      "no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    123\n\n    # 2\n    :abc\n";

    assert.equal(result, expected);
  });
});

it("buildKeyErrorMsg()", () => {
  const key = Type.atom("c");

  const map = Type.map([
    [Type.atom("b"), Type.integer(2)],
    [Type.atom("a"), Type.integer(1)],
  ]);

  const result = buildKeyErrorMsg(key, map);
  const expected = "key :c not found in:\n\n    %{a: 1, b: 2}\n";

  assert.equal(result, expected);
});

it("buildMatchErrorMsg()", () => {
  const result = buildMatchErrorMsg(Type.atom("abc"));
  const expected = "no match of right hand side value:\n\n    :abc\n";

  assert.equal(result, expected);
});

describe("buildMultiArgumentErrorMsg()", () => {
  it("builds a bullet per entry", () => {
    const result = buildMultiArgumentErrorMsg([
      [1, "my message 1"],
      [2, "my message 2"],
    ]);

    const expected =
      "errors were found at the given arguments:\n\n  * 1st argument: my message 1\n  * 2nd argument: my message 2\n";

    assert.equal(result, expected);
  });

  it("skips entries with a nullish message", () => {
    const result = buildMultiArgumentErrorMsg([
      [1, null],
      [2, "my message"],
    ]);

    const expected =
      "errors were found at the given arguments:\n\n  * 2nd argument: my message\n";

    assert.equal(result, expected);
  });
});

it("buildTryClauseErrorMsg()", () => {
  const result = buildTryClauseErrorMsg(Type.atom("abc"));
  const expected = "no try clause matching:\n\n    :abc\n";

  assert.equal(result, expected);
});

describe("buildUndefinedFunctionErrorMsg", () => {
  const module = Type.alias("Aaa.Bbb");

  it("module is available", () => {
    const result = buildUndefinedFunctionErrorMsg(module, "my_fun", 2);

    const expected = "function Aaa.Bbb.my_fun/2 is undefined or private";

    assert.equal(result, expected);
  });

  it("module is not available", () => {
    const result = buildUndefinedFunctionErrorMsg(module, "my_fun", 2, false);

    const expected =
      "function Aaa.Bbb.my_fun/2 is undefined (module Aaa.Bbb is not available). Make sure the module name is correct and has been specified in full (or that an alias has been defined)";

    assert.equal(result, expected);
  });
});
