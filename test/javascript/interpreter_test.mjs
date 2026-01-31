"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  contextFixture,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import {defineModule1Fixture as defineInterpreterModule1Fixture} from "./support/fixtures/ex_js_consistency/interpreter/module_1.mjs";
import {defineModule1Fixture as defineMatchOperatorModule1Fixture} from "./support/fixtures/ex_js_consistency/match_operator/module_1.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import Erlang from "../../assets/js/erlang/erlang.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import NodeTable from "../../assets/js/erts/node_table.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();
defineInterpreterModule1Fixture();
defineMatchOperatorModule1Fixture();

describe("Interpreter", () => {
  describe("accessKeywordListElement()", () => {
    const keywordList = Type.keywordList([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ]);

    it("keyword list has the given key", () => {
      const result = Interpreter.accessKeywordListElement(
        keywordList,
        Type.atom("b"),
      );

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("keyword list doesn't have the given key, no default value provided", () => {
      const result = Interpreter.accessKeywordListElement(
        keywordList,
        Type.atom("d"),
      );

      assert.isNull(result);
    });

    it("keyword list doesn't have the given key, default value is provided", () => {
      const result = Interpreter.accessKeywordListElement(
        keywordList,
        Type.atom("d"),
        Type.atom("my_default_value"),
      );

      assert.deepStrictEqual(result, Type.atom("my_default_value"));
    });
  });

  it("buildArgumentErrorMsg()", () => {
    const result = Interpreter.buildArgumentErrorMsg(2, "my message");

    const expected =
      "errors were found at the given arguments:\n\n  * 2nd argument: my message\n";

    assert.equal(result, expected);
  });

  it("buildBadFunctionErrorMsg()", () => {
    const term = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Interpreter.buildBadFunctionErrorMsg(term);
    const expected = "expected a function, got: %{a: 1, b: 2}";

    assert.equal(result, expected);
  });

  describe("buildContext()", () => {
    it("module undefined, vars undefined", () => {
      const result = Interpreter.buildContext();
      const expected = {module: null, vars: {}};

      assert.deepStrictEqual(result, expected);
    });

    it("module defined, string", () => {
      const result = Interpreter.buildContext({module: "MyModule"});
      const expected = {module: Type.atom("Elixir.MyModule"), vars: {}};

      assert.deepStrictEqual(result, expected);
    });

    it("module defined, boxed alias", () => {
      const result = Interpreter.buildContext({module: Type.alias("MyModule")});
      const expected = {module: Type.atom("Elixir.MyModule"), vars: {}};

      assert.deepStrictEqual(result, expected);
    });

    it("module defined, null", () => {
      const result = Interpreter.buildContext({module: null});
      const expected = {module: null, vars: {}};

      assert.deepStrictEqual(result, expected);
    });

    it("vars defined", () => {
      const result = Interpreter.buildContext({
        vars: {a: Type.integer(1), b: Type.integer(2)},
      });

      const expected = {
        module: null,
        vars: {a: Type.integer(1), b: Type.integer(2)},
      };

      assert.deepStrictEqual(result, expected);
    });
  });

  it("buildErlangErrorMsg()", () => {
    const result = Interpreter.buildErlangErrorMsg("my message");

    assert.equal(result, "Erlang error: my message");
  });

  describe("buildFunctionClauseErrorMsg()", () => {
    it("no args param given", () => {
      const result =
        Interpreter.buildFunctionClauseErrorMsg("MyModule.my_fun/2");

      const expected = "no function clause matching in MyModule.my_fun/2";

      assert.equal(result, expected);
    });

    it("0 args", () => {
      const result = Interpreter.buildFunctionClauseErrorMsg(
        "MyModule.my_fun/2",
        [],
      );

      const expected = "no function clause matching in MyModule.my_fun/2";

      assert.equal(result, expected);
    });

    it("1 arg", () => {
      const result = Interpreter.buildFunctionClauseErrorMsg(
        "MyModule.my_fun/2",
        [Type.integer(123)],
      );

      const expected =
        "no function clause matching in MyModule.my_fun/2\n\nThe following arguments were given to MyModule.my_fun/2:\n\n    # 1\n    123\n";

      assert.equal(result, expected);
    });

    it("2 args", () => {
      const result = Interpreter.buildFunctionClauseErrorMsg(
        "MyModule.my_fun/2",
        [Type.integer(123), Type.atom("abc")],
      );

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

    const result = Interpreter.buildKeyErrorMsg(key, map);
    const expected = "key :c not found in: %{a: 1, b: 2}";

    assert.equal(result, expected);
  });

  it("buildMatchErrorMsg()", () => {
    const result = Interpreter.buildMatchErrorMsg(Type.atom("abc"));
    const expected = "no match of right hand side value: :abc";

    assert.equal(result, expected);
  });

  it("buildProtocolUndefinedErrorMsg()", () => {
    const result = Interpreter.buildProtocolUndefinedErrorMsg(
      "String.Chars",
      Type.tuple([Type.integer(1), Type.integer(2)]),
    );

    const expected =
      "protocol String.Chars not implemented for type Tuple\n\nGot value:\n\n    {1, 2}";

    assert.equal(result, expected);
  });

  it("buildTooBigOutputErrorMsg()", () => {
    const result = Interpreter.buildTooBigOutputErrorMsg(
      "{MyModule, :my_fun, 3}",
    );

    const expected =
      "{MyModule, :my_fun, 3} can't be transpiled automatically to JavaScript, because its output is too big.\n" +
      "See what to do here: https://www.hologram.page/TODO";

    assert.equal(result, expected);
  });

  describe("buildUndefinedFunctionErrorMsg", () => {
    const module = Type.alias("Aaa.Bbb");

    it("module is available", () => {
      const result = Interpreter.buildUndefinedFunctionErrorMsg(
        module,
        "my_fun",
        2,
      );

      const expected = "function Aaa.Bbb.my_fun/2 is undefined or private";

      assert.equal(result, expected);
    });

    it("module is not available", () => {
      const result = Interpreter.buildUndefinedFunctionErrorMsg(
        module,
        "my_fun",
        2,
        false,
      );

      const expected =
        "function Aaa.Bbb.my_fun/2 is undefined (module Aaa.Bbb is not available). Make sure the module name is correct and has been specified in full (or that an alias has been defined)";

      assert.equal(result, expected);
    });
  });

  it("cloneContext()", () => {
    const context = {
      module: Type.atom("MyModule1"),
      vars: {
        a: Type.integer(1),
        b: Type.integer(2),
      },
    };

    const clone = Interpreter.cloneContext(context);

    assert.deepStrictEqual(clone, {
      module: Type.atom("MyModule1"),
      vars: {
        a: Type.integer(1),
        b: Type.integer(2),
      },
    });

    clone.module = Type.atom("MyModule2");
    clone.vars.b = Type.integer(20);

    assert.deepStrictEqual(context, {
      module: Type.atom("MyModule1"),
      vars: {
        a: Type.integer(1),
        b: Type.integer(2),
      },
    });

    assert.deepStrictEqual(clone, {
      module: Type.atom("MyModule2"),
      vars: {
        a: Type.integer(1),
        b: Type.integer(20),
      },
    });
  });

  describe("compareTerms()", () => {
    describe("different types", () => {
      it("first term smaller than second term", () => {
        const result = Interpreter.compareTerms(
          Type.integer(123),
          Type.atom("abc"),
        );

        assert.equal(result, -1);
      });

      it("first term bigger than second term", () => {
        const result = Interpreter.compareTerms(
          Type.atom("abc"),
          Type.integer(123),
        );

        assert.equal(result, 1);
      });
    });

    describe("atom type", () => {
      it("atom == atom", () => {
        const result = Interpreter.compareTerms(
          Type.atom("abc"),
          Type.atom("abc"),
        );

        assert.equal(result, 0);
      });

      it("atom < atom", () => {
        const result = Interpreter.compareTerms(
          Type.atom("aaa"),
          Type.atom("bbb"),
        );

        assert.equal(result, -1);
      });

      it("atom > atom", () => {
        const result = Interpreter.compareTerms(
          Type.atom("bbb"),
          Type.atom("aaa"),
        );

        assert.equal(result, 1);
      });

      it("unicode chars", () => {
        const result = Interpreter.compareTerms(
          Type.atom("álien"),
          Type.atom("office"),
        );

        assert.equal(result, 1);
      });
    });

    it("bitstring type", () => {
      const result = Interpreter.compareTerms(
        Type.bitstring("aaa"),
        Type.bitstring("bbb"),
      );

      assert.equal(result, -1);
    });

    describe("number types (float or integer)", () => {
      it("float == float", () => {
        const result = Interpreter.compareTerms(
          Type.float(1.23),
          Type.float(1.23),
        );

        assert.equal(result, 0);
      });

      it("integer == integer", () => {
        const result = Interpreter.compareTerms(
          Type.integer(123),
          Type.integer(123),
        );

        assert.equal(result, 0);
      });

      it("float == integer", () => {
        const result = Interpreter.compareTerms(
          Type.float(123.0),
          Type.integer(123),
        );

        assert.equal(result, 0);
      });

      it("integer == float", () => {
        const result = Interpreter.compareTerms(
          Type.integer(123),
          Type.float(123.0),
        );

        assert.equal(result, 0);
      });

      it("float < float", () => {
        const result = Interpreter.compareTerms(
          Type.float(1.23),
          Type.float(2.34),
        );

        assert.equal(result, -1);
      });

      it("float < integer", () => {
        const result = Interpreter.compareTerms(
          Type.float(1.23),
          Type.integer(2),
        );

        assert.equal(result, -1);
      });

      it("float > float", () => {
        const result = Interpreter.compareTerms(
          Type.float(2.34),
          Type.float(1.23),
        );

        assert.equal(result, 1);
      });

      it("float > integer", () => {
        const result = Interpreter.compareTerms(
          Type.float(2.34),
          Type.integer(1),
        );

        assert.equal(result, 1);
      });

      it("integer < integer", () => {
        const result = Interpreter.compareTerms(
          Type.integer(1),
          Type.integer(2),
        );

        assert.equal(result, -1);
      });

      it("integer < float", () => {
        const result = Interpreter.compareTerms(
          Type.integer(1),
          Type.float(2.34),
        );

        assert.equal(result, -1);
      });

      it("integer > integer", () => {
        const result = Interpreter.compareTerms(
          Type.integer(2),
          Type.integer(1),
        );

        assert.equal(result, 1);
      });

      it("integer > float", () => {
        const result = Interpreter.compareTerms(
          Type.integer(2),
          Type.float(1.23),
        );

        assert.equal(result, 1);
      });
    });

    describe("pid type", () => {
      it("pid == pid", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 111]),
          Type.pid("my_node@my_host", [1, 11, 111]),
        );

        assert.equal(result, 0);
      });

      it("pid < pid, difference in first segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [0, 11, 111]),
          Type.pid("my_node@my_host", [1, 11, 111]),
        );

        assert.equal(result, -1);
      });

      it("pid < pid, difference in second segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 10, 111]),
          Type.pid("my_node@my_host", [1, 11, 111]),
        );

        assert.equal(result, -1);
      });

      it("pid < pid, difference in third segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 110]),
          Type.pid("my_node@my_host", [1, 11, 111]),
        );

        assert.equal(result, -1);
      });

      it("pid > pid, difference in first segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 111]),
          Type.pid("my_node@my_host", [0, 11, 111]),
        );

        assert.equal(result, 1);
      });

      it("pid > pid, difference in second segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 111]),
          Type.pid("my_node@my_host", [1, 10, 111]),
        );

        assert.equal(result, 1);
      });

      it("pid > pid, difference in third segment", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 111]),
          Type.pid("my_node@my_host", [1, 11, 110]),
        );

        assert.equal(result, 1);
      });

      it("the third segment is compared first in turn", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 11, 110]),
          Type.pid("my_node@my_host", [0, 10, 111]),
        );

        assert.equal(result, -1);
      });

      it("the second segment is compared second in turn", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [1, 10, 111]),
          Type.pid("my_node@my_host", [0, 11, 111]),
        );

        assert.equal(result, -1);
      });

      it("the first segment is compared third in turn", () => {
        const result = Interpreter.compareTerms(
          Type.pid("my_node@my_host", [0, 11, 111]),
          Type.pid("my_node@my_host", [1, 11, 111]),
        );

        assert.equal(result, -1);
      });
    });

    describe("tuple type", () => {
      it("empty tuple == empty tuple", () => {
        const result = Interpreter.compareTerms(Type.tuple([]), Type.tuple([]));

        assert.equal(result, 0);
      });

      it("empty tuple < non-empty tuple", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([]),
          Type.tuple([Type.integer(1), Type.integer(2)]),
        );

        assert.equal(result, -1);
      });

      it("non-empty tuple > empty tuple", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(2)]),
          Type.tuple([]),
        );

        assert.equal(result, 1);
      });

      it("non-empty tuple == non-empty tuple", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(2)]),
          Type.tuple([Type.integer(1), Type.integer(2)]),
        );

        assert.equal(result, 0);
      });

      it("non-empty tuple < non-empty tuple, diffent item count", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(1)]),
          Type.tuple([Type.integer(1), Type.integer(1), Type.integer(1)]),
        );

        assert.equal(result, -1);
      });

      it("non-empty tuple < non-empty tuple, diffent items", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(2)]),
          Type.tuple([Type.integer(1), Type.integer(3)]),
        );

        assert.equal(result, -1);
      });

      it("non-empty tuple > non-empty tuple, diffent item count", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(1), Type.integer(1)]),
          Type.tuple([Type.integer(1), Type.integer(1)]),
        );

        assert.equal(result, 1);
      });

      it("non-empty tuple > non-empty tuple, diffent items", () => {
        const result = Interpreter.compareTerms(
          Type.tuple([Type.integer(1), Type.integer(3)]),
          Type.tuple([Type.integer(1), Type.integer(2)]),
        );

        assert.equal(result, 1);
      });
    });
  });

  describe("comprehension()", () => {
    let context, prevIntoFun, prevToListFun;

    beforeEach(() => {
      context = contextFixture({
        vars: {a: Type.integer(1), b: Type.integer(2)},
      });
      prevIntoFun = globalThis.Elixir_Enum["into/2"];

      globalThis.Elixir_Enum["into/2"] = (enumerable, _collectable) => {
        return enumerable;
      };

      prevToListFun = globalThis.Elixir_Enum["to_list/1"];

      globalThis.Elixir_Enum["to_list/1"] = (enumerable) => {
        return enumerable;
      };
    });

    afterEach(() => {
      globalThis.Elixir_Enum["into/2"] = prevIntoFun;
      globalThis.Elixir_Enum["to_list/1"] = prevToListFun;
    });

    describe("generator", () => {
      it("generates combinations of enumerables items", () => {
        // for x <- [1, 2], y <- [3, 4], do: {x, y}

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: (_context) => Type.list([Type.integer(1), Type.integer(2)]),
        };

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [],
          body: (_context) => Type.list([Type.integer(3), Type.integer(4)]),
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.map(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(1), Type.integer(3)]),
          Type.tuple([Type.integer(1), Type.integer(4)]),
          Type.tuple([Type.integer(2), Type.integer(3)]),
          Type.tuple([Type.integer(2), Type.integer(4)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("ignores enumerable items that don't match the pattern", () => {
        // for {11, x} <- [1, {11, 2}, 3, {11, 4}],
        //     {12, y} <- [5, {12, 6}, 7, {12, 8}],
        //     do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([
            Type.integer(1),
            Type.tuple([Type.integer(11), Type.integer(2)]),
            Type.integer(3),
            Type.tuple([Type.integer(11), Type.integer(4)]),
          ]);

        const generator1 = {
          match: Type.tuple([Type.integer(11), Type.variablePattern("x")]),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([
            Type.integer(5),
            Type.tuple([Type.integer(12), Type.integer(6)]),
            Type.integer(7),
            Type.tuple([Type.integer(12), Type.integer(8)]),
          ]);

        const generator2 = {
          match: Type.tuple([Type.integer(12), Type.variablePattern("y")]),
          guards: [],
          body: enumerable2,
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(2), Type.integer(6)]),
          Type.tuple([Type.integer(2), Type.integer(8)]),
          Type.tuple([Type.integer(4), Type.integer(6)]),
          Type.tuple([Type.integer(4), Type.integer(8)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("uses Enum.to_list/1 to convert generator enumerables to lists", () => {
        // for x <- [1, 2], y <- [3, 4], do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2)]);

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(3), Type.integer(4)]);

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [],
          body: enumerable2,
        };

        const stub = sinon
          .stub(Elixir_Enum, "to_list/1")
          .callsFake((enumerable) => enumerable);

        Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.map(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        sinon.assert.calledWith(stub, enumerable1(context));
        sinon.assert.calledWith(stub, enumerable2(context));

        Elixir_Enum["to_list/1"].restore();
      });
    });

    describe("guards", () => {
      it("single guard", () => {
        // for x when x != 2 <- [1, 2, 3],
        //     y when y != 4 <- [4, 5, 6],
        //     do: {x, y}
        //
        // for x when :erlang."/="(x, 2) <- [1, 2, 3],
        //     y when :erlang."/="(y, 4) <- [4, 5, 6],
        //     do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

        const guard1a = (context) =>
          Erlang["/=/2"](context.vars.x, Type.integer(2));

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [guard1a],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(4), Type.integer(5), Type.integer(6)]);

        const guard2a = (context) =>
          Erlang["/=/2"](context.vars.y, Type.integer(4));

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [guard2a],
          body: enumerable2,
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(1), Type.integer(5)]),
          Type.tuple([Type.integer(1), Type.integer(6)]),
          Type.tuple([Type.integer(3), Type.integer(5)]),
          Type.tuple([Type.integer(3), Type.integer(6)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("multiple guards", () => {
        // for x when x == 2 when x == 4 <- [1, 2, 3, 4],
        //     y when y == 5 when y == 7 <- [5, 6, 7, 8],
        //     do: {x, y}
        //
        // for x when :erlang."=="(x, 2) when :erlang."=="(x, 4) <- [1, 2, 3, 4],
        //     y when :erlang."=="(y, 5) when :erlang."=="(y, 7) <- [5, 6, 7, 8],
        //     do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([
            Type.integer(1),
            Type.integer(2),
            Type.integer(3),
            Type.integer(4),
          ]);

        const guard1a = (context) =>
          Erlang["==/2"](context.vars.x, Type.integer(2));
        const guard1b = (context) =>
          Erlang["==/2"](context.vars.x, Type.integer(4));

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [guard1a, guard1b],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([
            Type.integer(5),
            Type.integer(6),
            Type.integer(7),
            Type.integer(8),
          ]);

        const guard2a = (context) =>
          Erlang["==/2"](context.vars.y, Type.integer(5));
        const guard2b = (context) =>
          Erlang["==/2"](context.vars.y, Type.integer(7));

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [guard2a, guard2b],
          body: enumerable2,
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(2), Type.integer(5)]),
          Type.tuple([Type.integer(2), Type.integer(7)]),
          Type.tuple([Type.integer(4), Type.integer(5)]),
          Type.tuple([Type.integer(4), Type.integer(7)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("can access variables from comprehension outer scope", () => {
        // for x when x != b <- [1, 2, 3], do: x

        const enumerable = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

        const guard = (context) =>
          Erlang["/=/2"](context.vars.x, context.vars.b);

        const generator = {
          match: Type.variablePattern("x"),
          guards: [guard],
          body: enumerable,
        };

        const result = Interpreter.comprehension(
          [generator],
          [],
          Type.list(),
          false,
          (context) => context.vars.x,
          context,
        );

        const expected = Type.list([Type.integer(1), Type.integer(3)]);

        assert.deepStrictEqual(result, expected);
      });

      it("can access variables pattern matched in preceding guards", () => {
        // for x <- [1, 2], y when x != 1 <- [3, 4], do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2)]);

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(3), Type.integer(4)]);

        const guard2 = (context) =>
          Erlang["/=/2"](context.vars.x, Type.integer(1));

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [guard2],
          body: enumerable2,
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(2), Type.integer(3)]),
          Type.tuple([Type.integer(2), Type.integer(4)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("errors raised inside generators are not caught", () => {
        const enumerable = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

        const guard = (_context) =>
          Interpreter.raiseArgumentError("my message");

        const generator = {
          match: Type.variablePattern("x"),
          guards: [guard],
          body: enumerable,
        };

        assertBoxedError(
          () =>
            Interpreter.comprehension(
              [generator],
              [],
              Type.list(),
              false,
              (context) => context.vars.x,
              context,
            ),
          "ArgumentError",
          "my message",
        );
      });
    });

    describe("filters", () => {
      it("remove combinations that don't fullfill specified conditions", () => {
        // for x <- [1, 2, 3],
        //     y <- [4, 5, 6],
        //     x + y < 8,
        //     y - x > 2,
        //     do: {x, y}

        // for x <- [1, 2, 3],
        //     y <- [4, 5, 6],
        //     :erlang.<(:erlang.+(x, y), 8),
        //     :erlang.>(:erlang.-(y, x), 2),
        //     do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(4), Type.integer(5), Type.integer(6)]);

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [],
          body: enumerable2,
        };

        const filters = [
          (context) =>
            Erlang["</2"](
              Erlang["+/2"](context.vars.x, context.vars.y),
              Type.integer(8),
            ),
          (context) =>
            Erlang[">/2"](
              Erlang["-/2"](context.vars.y, context.vars.x),
              Type.integer(2),
            ),
        ];

        const result = Interpreter.comprehension(
          [generator1, generator2],
          filters,
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(1), Type.integer(4)]),
          Type.tuple([Type.integer(1), Type.integer(5)]),
          Type.tuple([Type.integer(1), Type.integer(6)]),
          Type.tuple([Type.integer(2), Type.integer(5)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("can access variables from comprehension outer scope", () => {
        // for x <- [1, 2, 3], x != b, do: x

        const enumerable = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

        const generator = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable,
        };

        const filter = (context) =>
          Erlang["/=/2"](context.vars.x, context.vars.b);

        const result = Interpreter.comprehension(
          [generator],
          [filter],
          Type.list(),
          false,
          (context) => context.vars.x,
          context,
        );

        const expected = Type.list([Type.integer(1), Type.integer(3)]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("unique", () => {
      it("non-unique items are removed if 'uniq' option is set to true", () => {
        // for x <- [1, 2, 1], y <- [3, 4, 3], do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2), Type.integer(1)]);

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(3), Type.integer(4), Type.integer(3)]);

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [],
          body: enumerable2,
        };

        const result = Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.list(),
          true,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(1), Type.integer(3)]),
          Type.tuple([Type.integer(1), Type.integer(4)]),
          Type.tuple([Type.integer(2), Type.integer(3)]),
          Type.tuple([Type.integer(2), Type.integer(4)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });
    });

    describe("mapper", () => {
      it("can access variables from comprehension outer scope", () => {
        // for x <- [1, 2], do: {x, b}

        const enumerable = (_context) =>
          Type.list([Type.integer(1), Type.integer(2)]);

        const generator = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable,
        };

        const result = Interpreter.comprehension(
          [generator],
          [],
          Type.list(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.b]),
          context,
        );

        const expected = Type.list([
          Type.tuple([Type.integer(1), Type.integer(2)]),
          Type.tuple([Type.integer(2), Type.integer(2)]),
        ]);

        assert.deepStrictEqual(result, expected);
      });

      it("uses Enum.into/2 to insert the comprehension result into a collectable", () => {
        // for x <- [1, 2], y <- [3, 4], do: {x, y}

        const enumerable1 = (_context) =>
          Type.list([Type.integer(1), Type.integer(2)]);

        const generator1 = {
          match: Type.variablePattern("x"),
          guards: [],
          body: enumerable1,
        };

        const enumerable2 = (_context) =>
          Type.list([Type.integer(3), Type.integer(4)]);

        const generator2 = {
          match: Type.variablePattern("y"),
          guards: [],
          body: enumerable2,
        };

        const stub = sinon
          .stub(Elixir_Enum, "into/2")
          .callsFake((enumerable, _collectable) => enumerable);

        Interpreter.comprehension(
          [generator1, generator2],
          [],
          Type.map(),
          false,
          (context) => Type.tuple([context.vars.x, context.vars.y]),
          context,
        );

        const expectedArg = Type.list([
          Type.tuple([Type.integer(1), Type.integer(3)]),
          Type.tuple([Type.integer(1), Type.integer(4)]),
          Type.tuple([Type.integer(2), Type.integer(3)]),
          Type.tuple([Type.integer(2), Type.integer(4)]),
        ]);

        assert.isTrue(stub.calledOnceWith(expectedArg));

        Elixir_Enum["into/2"].restore();
      });
    });
  });

  describe("consOperator()", () => {
    it("constructs a proper list when the tail param is a proper non-empty list", () => {
      const head = Type.integer(1);
      const tail = Type.list([Type.integer(2), Type.integer(3)]);
      const result = Interpreter.consOperator(head, tail);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("constructs a proper list when the tail param is an empty list", () => {
      const head = Type.integer(1);
      const tail = Type.list();
      const result = Interpreter.consOperator(head, tail);
      const expected = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expected);
    });

    it("constructs improper list when the tail is not a list", () => {
      const head = Type.integer(1);
      const tail = Type.atom("abc");
      const result = Interpreter.consOperator(head, tail);
      const expected = Type.improperList([Type.integer(1), Type.atom("abc")]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("defineElixirFunction()", () => {
    beforeEach(() => {
      // def my_fun_a(1), do: :expr_1
      // def my_fun_a(2), do: :expr_2
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_a", 1, "public", [
        {
          params: (_context) => [Type.integer(1)],
          guards: [],
          body: (_context) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_context) => [Type.integer(2)],
          guards: [],
          body: (_context) => {
            return Type.atom("expr_2");
          },
        },
      ]);
    });

    afterEach(() => {
      delete globalThis.Elixir_Aaa_Bbb;
    });

    it("initiates the module global var if it is not initiated yet", () => {
      Interpreter.defineElixirFunction("Ddd", "my_fun_d", 4, "public", []);

      assert.isDefined(globalThis.Elixir_Ddd);
      assert.isDefined(globalThis.Elixir_Ddd["my_fun_d/4"]);

      assert.deepStrictEqual(
        globalThis.Elixir_Ddd.__exModule__,
        Type.alias("Ddd"),
      );

      assert.equal(globalThis.Elixir_Ddd.__jsName__, "Elixir_Ddd");

      // cleanup
      delete globalThis.Elixir_Ddd;
    });

    it("appends to the module global var if it is already initiated", () => {
      globalThis.Elixir_Eee = {
        __exModule__: Type.alias("Eee"),
        __exports__: new Set(),
        __jsName__: "Elixir_Eee",
        "dummy/1": "dummy_body",
      };

      Interpreter.defineElixirFunction("Eee", "my_fun_e", 5, "public", []);

      assert.isDefined(globalThis.Elixir_Eee);
      assert.isDefined(globalThis.Elixir_Eee["my_fun_e/5"]);
      assert.equal(globalThis.Elixir_Eee["dummy/1"], "dummy_body");

      // cleanup
      delete globalThis.Elixir_Eee;
    });

    it("defines a function with multiple params", () => {
      // def my_fun_e(1, 2, 3), do: :ok
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_e", 3, "public", [
        {
          params: (_context) => [
            Type.integer(1),
            Type.integer(2),
            Type.integer(3),
          ],
          guards: [],
          body: (_context) => {
            return Type.atom("ok");
          },
        },
      ]);

      const result = globalThis.Elixir_Aaa_Bbb["my_fun_e/3"](
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      );

      assert.deepStrictEqual(result, Type.atom("ok"));
    });

    it("defines a function which runs the first matching clause", () => {
      const result = globalThis.Elixir_Aaa_Bbb["my_fun_a/1"](Type.integer(1));
      assert.deepStrictEqual(result, Type.atom("expr_1"));
    });

    it("defines a function which ignores not matching clauses", () => {
      const result = globalThis.Elixir_Aaa_Bbb["my_fun_a/1"](Type.integer(2));
      assert.deepStrictEqual(result, Type.atom("expr_2"));
    });

    it("defines a function which runs guards for each tried clause", () => {
      // def my_fun_b(x) when x == 1, do: :expr_1
      // def my_fun_b(y) when y == 2, do: :expr_2
      // def my_fun_b(z) when z == 3, do: :expr_3
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_b", 1, "public", [
        {
          params: (_context) => [Type.variablePattern("x")],
          guards: [
            (context) => Erlang["==/2"](context.vars.x, Type.integer(1)),
          ],
          body: (_context) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_context) => [Type.variablePattern("y")],
          guards: [
            (context) => Erlang["==/2"](context.vars.y, Type.integer(2)),
          ],
          body: (_context) => {
            return Type.atom("expr_2");
          },
        },
        {
          params: (_context) => [Type.variablePattern("z")],
          guards: [
            (context) => Erlang["==/2"](context.vars.z, Type.integer(3)),
          ],
          body: (_context) => {
            return Type.atom("expr_3");
          },
        },
      ]);

      const result = globalThis.Elixir_Aaa_Bbb["my_fun_b/1"](Type.integer(3));

      assert.deepStrictEqual(result, Type.atom("expr_3"));
    });

    it("defines a function with multiple guards", () => {
      // def my_fun_b(x) when x == 1 when x == 2, do: x
      //
      // def my_fun_b(x) when :erlang.==(x, 1) when :erlang.==(x, 2), do: x
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_b", 1, "public", [
        {
          params: (_context) => [Type.variablePattern("x")],
          guards: [
            (context) => Erlang["==/2"](context.vars.x, Type.integer(1)),
            (context) => Erlang["==/2"](context.vars.x, Type.integer(2)),
          ],
          body: (context) => {
            return context.vars.x;
          },
        },
      ]);

      const result1 = globalThis.Elixir_Aaa_Bbb["my_fun_b/1"](Type.integer(1));
      assert.deepStrictEqual(result1, Type.integer(1));

      const result2 = globalThis.Elixir_Aaa_Bbb["my_fun_b/1"](Type.integer(2));
      assert.deepStrictEqual(result2, Type.integer(2));

      assertBoxedError(
        () => globalThis.Elixir_Aaa_Bbb["my_fun_b/1"](Type.integer(3)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("Aaa.Bbb.my_fun_b/1", [
          Type.integer(3),
        ]),
      );
    });

    it("defines a function which clones vars for each clause", () => {
      // def my_fun_c(x) when x == 1, do: :expr_1
      // def my_fun_c(x) when x == 2, do: :expr_2
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_c", 1, "public", [
        {
          params: (_context) => [Type.variablePattern("x")],
          guards: [
            (context) => Erlang["==/2"](context.vars.x, Type.integer(1)),
          ],
          body: (_context) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_context) => [Type.variablePattern("x")],
          guards: [
            (context) => Erlang["==/2"](context.vars.x, Type.integer(2)),
          ],
          body: (_context) => {
            return Type.atom("expr_2");
          },
        },
      ]);

      const result = globalThis.Elixir_Aaa_Bbb["my_fun_c/1"](Type.integer(2));

      assert.deepStrictEqual(result, Type.atom("expr_2"));
    });

    it("raises FunctionClauseError if there are no matching clauses", () => {
      assertBoxedError(
        () => globalThis.Elixir_Aaa_Bbb["my_fun_a/1"](Type.integer(3)),
        "FunctionClauseError",
        Interpreter.buildFunctionClauseErrorMsg("Aaa.Bbb.my_fun_a/1", [
          Type.integer(3),
        ]),
      );
    });

    it("defines a function which has match operator in params", () => {
      // def my_fun_d(x = 1 = y), do: x + y
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_d", 1, "public", [
        {
          params: (context) => [
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("y"),
                Type.integer(1),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ],
          guards: [],
          body: (context) => {
            return Erlang["+/2"](context.vars.x, context.vars.y);
          },
        },
      ]);

      const result = globalThis.Elixir_Aaa_Bbb["my_fun_d/1"](Type.integer(1));

      assert.deepStrictEqual(result, Type.integer(2));
    });

    it("flags public functions as module exports", () => {
      Interpreter.defineElixirFunction("Ddd", "my_fun_d", 4, "public", []);

      assert.deepStrictEqual(
        globalThis.Elixir_Ddd.__exports__,
        new Set(["my_fun_d/4"]),
      );

      // cleanup
      delete globalThis.Elixir_Ddd;
    });

    it("doesn't flag private functions as module exports", () => {
      Interpreter.defineElixirFunction("Ddd", "my_fun_d", 4, "private", []);

      assert.deepStrictEqual(globalThis.Elixir_Ddd.__exports__, new Set());

      // cleanup
      delete globalThis.Elixir_Ddd;
    });

    it("errors raised inside function body are not caught", () => {
      Interpreter.defineElixirFunction("Aaa.Bbb", "my_fun_f", 0, "public", [
        {
          params: () => [],
          guards: [],
          body: (_context) => Interpreter.raiseArgumentError("my message"),
        },
      ]);

      assertBoxedError(
        () => globalThis.Elixir_Aaa_Bbb["my_fun_f/0"](),
        "ArgumentError",
        "my message",
      );
    });

    it("raises UndefinedFunctionError when undefined Elixir/Erlang function is being called", () => {
      assertBoxedError(
        () => globalThis.Elixir_Aaa_Bbb["my_fun_x/5"],
        "UndefinedFunctionError",
        Interpreter.buildUndefinedFunctionErrorMsg(
          Type.alias("Aaa.Bbb"),
          "my_fun_x",
          5,
        ),
      );
    });
  });

  describe("defineErlangFunction()", () => {
    beforeEach(() => {
      Interpreter.defineErlangFunction("aaa_bbb", "my_fun_a", 2, () =>
        Type.atom("expr_a"),
      );
    });

    afterEach(() => {
      delete globalThis.Erlang_Aaa_Bbb;
    });

    it("initiates the module global var if it is not initiated yet", () => {
      Interpreter.defineErlangFunction("ddd", "my_fun_d", 3, []);

      assert.isDefined(globalThis.Erlang_Ddd);
      assert.isDefined(globalThis.Erlang_Ddd["my_fun_d/3"]);

      // cleanup
      delete globalThis.Erlang_Ddd;
    });

    it("appends to the module global var if it is already initiated", () => {
      globalThis.Erlang_Eee = {dummy: "dummy"};
      Interpreter.defineErlangFunction("eee", "my_fun_e", 1, []);

      assert.isDefined(globalThis.Erlang_Eee);
      assert.isDefined(globalThis.Erlang_Eee["my_fun_e/1"]);
      assert.equal(globalThis.Erlang_Eee.dummy, "dummy");

      // cleanup
      delete globalThis.Erlang_Eee;
    });

    it("defines function", () => {
      const result = globalThis.Erlang_Aaa_Bbb["my_fun_a/2"](Type.integer(1));
      assert.deepStrictEqual(result, Type.atom("expr_a"));
    });
  });

  describe("defineManuallyPortedFunction()", () => {
    beforeEach(() => delete globalThis.Elixir_MyModuleExName);

    it("initializes function's module proxy if it hasn't been initialized", () => {
      Interpreter.defineManuallyPortedFunction(
        "MyModuleExName",
        "my_defined_fun/3",
        "public",
        () => "my_defined_fun/3 result",
      );

      assertBoxedError(
        () => globalThis.Elixir_MyModuleExName["my_undefined_fun/3"],
        "UndefinedFunctionError",
        Interpreter.buildUndefinedFunctionErrorMsg(
          Type.alias("MyModuleExName"),
          "my_undefined_fun",
          3,
        ),
      );
    });

    it("makes the function available through its module proxy", () => {
      Interpreter.defineManuallyPortedFunction(
        "MyModuleExName",
        "my_defined_fun/3",
        "public",
        () => "my_defined_fun/3 result",
      );

      assert.equal(
        globalThis.Elixir_MyModuleExName["my_defined_fun/3"](),
        "my_defined_fun/3 result",
      );
    });

    it("adds the function to the list of module exports if it is public", () => {
      Interpreter.defineManuallyPortedFunction(
        "MyModuleExName",
        "my_defined_fun/3",
        "public",
        () => "my_defined_fun/3 result",
      );

      assert.deepStrictEqual(
        globalThis.Elixir_MyModuleExName.__exports__,
        new Set(["my_defined_fun/3"]),
      );
    });

    it("doesn't add the function to the list of module exports if it is private", () => {
      Interpreter.defineManuallyPortedFunction(
        "MyModuleExName",
        "my_defined_fun/3",
        "private",
        () => "my_defined_fun/3 result",
      );

      assert.deepStrictEqual(
        globalThis.Elixir_MyModuleExName.__exports__,
        new Set([]),
      );
    });
  });

  describe("defineNotImplementedErlangFunction()", () => {
    beforeEach(() => {
      Interpreter.defineNotImplementedErlangFunction("aaa_bbb", "my_fun_a", 2);
    });

    afterEach(() => {
      delete globalThis.Erlang_Aaa_Bbb;
    });

    it("initiates the module global var if it is not initiated yet", () => {
      Interpreter.defineNotImplementedErlangFunction("ddd", "my_fun_d", 3, []);

      assert.isDefined(globalThis.Erlang_Ddd);
      assert.isDefined(globalThis.Erlang_Ddd["my_fun_d/3"]);

      // cleanup
      delete globalThis.Erlang_Ddd;
    });

    it("appends to the module global var if it is already initiated", () => {
      globalThis.Erlang_Eee = {dummy: "dummy"};
      Interpreter.defineNotImplementedErlangFunction("eee", "my_fun_e", 1, []);

      assert.isDefined(globalThis.Erlang_Eee);
      assert.isDefined(globalThis.Erlang_Eee["my_fun_e/1"]);
      assert.equal(globalThis.Erlang_Eee.dummy, "dummy");

      // cleanup
      delete globalThis.Erlang_Eee;
    });

    it("defines a function which raises an exception with instructions", () => {
      const expectedMessage =
        `Function :aaa_bbb.my_fun_a/2 is not yet ported.\n` +
        `  * Check implementation status: https://hologram.page/reference/client-runtime\n` +
        `  * If the function is not marked 'in progress' and is critical for your project, you may request it here: https://github.com/bartblast/hologram/issues`;

      assert.throw(
        () =>
          globalThis.Erlang_Aaa_Bbb["my_fun_a/2"](
            Type.integer(1),
            Type.integer(2),
          ),
        Error,
        expectedMessage,
      );
    });
  });

  describe("dotOperator()", () => {
    it("handles remote function call", () => {
      // setup
      globalThis.Elixir_MyModule = {
        "my_fun/0": () => {
          return Type.integer(123);
        },
      };

      const left = Type.alias("MyModule");
      const right = Type.atom("my_fun");
      const result = Interpreter.dotOperator(left, right);

      assert.deepStrictEqual(result, Type.integer(123));

      // cleanup
      delete globalThis.Elixir_MyModule;
    });

    it("handles map key access", () => {
      const key = Type.atom("b");
      const value = Type.integer(2);

      const left = Type.map([
        [Type.atom("a"), Type.integer(1)],
        [key, value],
      ]);

      const result = Interpreter.dotOperator(left, key);

      assert.deepStrictEqual(result, value);
    });
  });

  describe("evaluateJavaScriptCode()", () => {
    it("single statement with semicolon", () => {
      const code = "return 123;";
      const result = Interpreter.evaluateJavaScriptCode(code);

      assert.equal(result, 123);
    });

    it("single statement without semicolon", () => {
      const code = "return 123";
      const result = Interpreter.evaluateJavaScriptCode(code);

      assert.equal(result, 123);
    });

    it("multiple statements with semicolons", () => {
      const code = `
        const a = 1;
        const b = 2;
        return a + b;
      `;

      const result = Interpreter.evaluateJavaScriptCode(code);

      assert.equal(result, 3);
    });

    it("multiple statements without semicolons", () => {
      const code = `
        const a = 1
        const b = 2
        return a + b
      `;

      const result = Interpreter.evaluateJavaScriptCode(code);

      assert.equal(result, 3);
    });

    it("using context, Type and Interpreter", () => {
      // %{a: 1, b: 2}.a
      const code =
        'return Interpreter.dotOperator(Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), context.vars.x]]), Type.atom("a"))';

      const result = Interpreter.evaluateJavaScriptCode(code);

      assert.deepStrictEqual(result, Type.integer(1));
    });
  });

  it("evaluateJavaScriptExpression()", () => {
    // %{a: 1, b: 2}.a
    const code =
      'Interpreter.dotOperator(Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), context.vars.x]]), Type.atom("a"))';

    const result = Interpreter.evaluateJavaScriptExpression(code);

    assert.deepStrictEqual(result, Type.integer(1));
  });

  it("getErrorMessage()", () => {
    const errorStruct = Type.errorStruct("MyError", "my message");
    const jsError = new HologramBoxedError(errorStruct);
    const result = Interpreter.getErrorMessage(jsError);

    assert.equal(result, "my message");
  });

  it("getErrorType()", () => {
    const errorStruct = Type.errorStruct("MyError", "my message");
    const jsError = new HologramBoxedError(errorStruct);
    const result = Interpreter.getErrorType(jsError);

    assert.equal(result, "MyError");
  });

  describe("getStructuralComparisonTypeOrder()", () => {
    it("float", () => {
      const result = Interpreter.getStructuralComparisonTypeOrder(
        Type.float(123.0),
      );

      assert.equal(result, 1);
    });

    it("integer", () => {
      const result = Interpreter.getStructuralComparisonTypeOrder(
        Type.integer(123),
      );

      assert.equal(result, 1);
    });

    it("non-number", () => {
      const result = Interpreter.getStructuralComparisonTypeOrder(
        Type.atom("abc"),
      );

      assert.equal(result, 2);
    });
  });

  // Keep Elixir consistency tests in sync: test/elixir/hologram/ex_js_consistency/interpreter_test.exs ("inspect" section).
  describe("inspect()", () => {
    describe("anonymous function", () => {
      const clauses = ["clause_dummy_1", "clause_dummy_2"];
      const context = contextFixture();

      // Client result for non-capture anonymous function is intentionally different than server result.
      it("non-capture", () => {
        const anonFun = Type.anonymousFunction(2, clauses, context);

        assert.equal(Interpreter.inspect(anonFun), "anonymous function fn/2");
      });

      // Case not possible on the client - function captures are always encoded as remote function captures.
      // it("local function capture")

      it("remote function capture", () => {
        const anonFun = Type.functionCapture(
          "MyModule",
          "my_fun",
          2,
          clauses,
          context,
        );

        assert.equal(Interpreter.inspect(anonFun), "&MyModule.my_fun/2");
      });
    });

    describe("atom", () => {
      it("true", () => {
        const result = Interpreter.inspect(Type.boolean(true));
        assert.equal(result, "true");
      });

      it("false", () => {
        const result = Interpreter.inspect(Type.boolean(false));
        assert.equal(result, "false");
      });

      it("nil", () => {
        const result = Interpreter.inspect(Type.nil());
        assert.equal(result, "nil");
      });

      it("module alias", () => {
        const result = Interpreter.inspect(Type.alias("Aaa.Bbb"));
        assert.equal(result, "Aaa.Bbb");
      });

      it("non-boolean and non-nil", () => {
        const result = Interpreter.inspect(Type.atom("abc"));
        assert.equal(result, ":abc");
      });
    });

    describe("bitstring", () => {
      describe("text", () => {
        it("empty", () => {
          const result = Interpreter.inspect(Type.bitstring(""));
          assert.equal(result, '""');
        });

        it("ASCII", () => {
          const result = Interpreter.inspect(Type.bitstring("abc"));
          assert.equal(result, '"abc"');
        });

        it("Unicode", () => {
          const result = Interpreter.inspect(Type.bitstring("全息图"));
          assert.equal(result, '"全息图"');
        });

        it("non-printable", () => {
          const result = Interpreter.inspect(Type.bitstring("a\x01b"));
          assert.equal(result, "<<97, 1, 98>>");
        });
      });

      describe("bytes", () => {
        it("that can be encoded as text", () => {
          // "abc"
          const result = Interpreter.inspect(Bitstring.fromBytes([97, 98, 99]));
          assert.equal(result, '"abc"');
        });

        it("byte-aligned, single", () => {
          const result = Interpreter.inspect(Bitstring.fromBytes([255]));
          assert.equal(result, "<<255>>");
        });

        it("byte-aligned, multiple", () => {
          const result = Interpreter.inspect(Bitstring.fromBytes([255, 254]));
          assert.equal(result, "<<255, 254>>");
        });

        it("not byte-aligned, single", () => {
          const result = Interpreter.inspect(Type.bitstring([1, 1]));
          assert.equal(result, "<<3::size(2)>>");
        });

        it("not byte-aligned, multiple", () => {
          const result = Interpreter.inspect(
            // prettier-ignore
            Type.bitstring([
              1, 1, 0, 0, 1, 1, 0, 0,
              1, 0, 1, 0, 1, 0, 1, 0,
              1, 1,
            ]),
          );

          assert.equal(result, "<<204, 170, 3::size(2)>>");
        });
      });
    });

    describe("float", () => {
      it("integer-representable", () => {
        const result = Interpreter.inspect(Type.float(123.0));
        assert.equal(result, "123.0");
      });

      it("not integer-representable", () => {
        const result = Interpreter.inspect(Type.float(123.45));
        assert.equal(result, "123.45");
      });
    });

    it("integer", () => {
      const result = Interpreter.inspect(Type.integer(123));
      assert.equal(result, "123");
    });

    describe("list", () => {
      it("empty", () => {
        const result = Interpreter.inspect(Type.list());
        assert.equal(result, "[]");
      });

      it("proper", () => {
        const result = Interpreter.inspect(
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        );

        assert.equal(result, "[1, 2, 3]");
      });

      it("improper", () => {
        const result = Interpreter.inspect(
          Type.improperList([
            Type.integer(1),
            Type.integer(2),
            Type.integer(3),
          ]),
        );

        assert.equal(result, "[1, 2 | 3]");
      });

      describe("keyword list", () => {
        it("single item", () => {
          const term = Type.keywordList([[Type.atom("a"), Type.integer(1)]]);

          const result = Interpreter.inspect(term);

          assert.equal(result, "[a: 1]");
        });

        it("multiple items", () => {
          const term = Type.keywordList([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(2)],
          ]);

          const result = Interpreter.inspect(term);

          assert.equal(result, "[a: 1, b: 2]");
        });
      });
    });

    describe("map", () => {
      const map = Type.map([
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("a"), Type.integer(1)],
      ]);

      it("empty", () => {
        const result = Interpreter.inspect(Type.map());
        assert.equal(result, "%{}");
      });

      it("with atom keys", () => {
        const map = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.atom("b"), Type.bitstring("xyz")],
        ]);

        const result = Interpreter.inspect(map);

        assert.equal(result, '%{a: 1, b: "xyz"}');
      });

      it("with non-atom keys", () => {
        const map = Type.map([
          [Type.integer(9), Type.bitstring("xyz")],
          [Type.bitstring("abc"), Type.float(2.3)],
        ]);

        const result = Interpreter.inspect(map);

        assert.equal(result, '%{9 => "xyz", "abc" => 2.3}');
      });

      it("sort_maps opt is not defined", () => {
        const result = Interpreter.inspect(map);

        assert.equal(result, "%{b: 2, a: 1}");
      });

      it("sort_maps opt is set to true", () => {
        const opts = Type.keywordList([
          [
            Type.atom("custom_options"),
            Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
          ],
        ]);

        const result = Interpreter.inspect(map, opts);

        assert.equal(result, "%{a: 1, b: 2}");
      });

      it("sort_maps opt is set to false", () => {
        const opts = Type.keywordList([
          [
            Type.atom("custom_options"),
            Type.keywordList([[Type.atom("sort_maps"), Type.boolean(false)]]),
          ],
        ]);

        const result = Interpreter.inspect(map, opts);

        assert.equal(result, "%{b: 2, a: 1}");
      });

      describe("structs", () => {
        describe("range", () => {
          it("step == 1", () => {
            const result = Interpreter.inspect(Type.range(123, 234, 1));
            assert.equal(result, "123..234");
          });

          it("step > 1", () => {
            const result = Interpreter.inspect(Type.range(123, 234, 345));
            assert.equal(result, "123..234//345");
          });
        });
      });
    });

    it("PID", () => {
      const term = Type.pid("my_node@my_host", [0, 11, 222], "client");
      const result = Interpreter.inspect(term);

      assert.equal(result, "#PID<0.11.222>");
    });

    it("port", () => {
      const term = Type.port("my_node", [0, 11], "server");
      const result = Interpreter.inspect(term);

      assert.equal(result, "#Port<0.11>");
    });

    describe("reference", () => {
      it("client node", () => {
        const term = Type.reference(NodeTable.CLIENT_NODE, 4, [3, 2, 1]);
        const result = Interpreter.inspect(term);

        assert.equal(result, "#Reference<0.1.2.3>");
      });

      it("server node", () => {
        const term = Type.reference("my_node@my_host", 7, [6, 5, 4]);
        const result = Interpreter.inspect(term);

        assert.equal(result, "#Reference<1.4.5.6>");
      });
    });

    describe("tuple", () => {
      it("empty", () => {
        const result = Interpreter.inspect(Type.tuple([]));
        assert.equal(result, "{}");
      });

      it("non-empty", () => {
        const result = Interpreter.inspect(
          Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
        );

        assert.equal(result, "{1, 2, 3}");
      });
    });
  });

  describe("inspectModuleJsName()", () => {
    it("inspects Elixir module name", () => {
      const result = Interpreter.inspectModuleJsName("Elixir_Aaa_Bbb_Ccc");
      assert.deepStrictEqual(result, "Aaa.Bbb.Ccc");
    });

    it("inspects 'Erlang' module name", () => {
      const result = Interpreter.inspectModuleJsName("Erlang");
      assert.deepStrictEqual(result, ":erlang");
    });

    it("inspects Erlang standard lib module name", () => {
      const result = Interpreter.inspectModuleJsName("Erlang_Uri_String");
      assert.deepStrictEqual(result, ":uri_string");
    });
  });

  describe("isEqual()", () => {
    // non-number == non-number
    it("returns true for a boxed non-number equal to another boxed non-number", () => {
      const left = Type.boolean(true);
      const right = Type.boolean(true);
      const result = Interpreter.isEqual(left, right);

      assert.isTrue(result);
    });

    // non-number != non-number
    it("returns false for a boxed non-number not equal to another boxed non-number", () => {
      const left = Type.boolean(true);
      const right = Type.bitstring("abc");
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // integer == integer
    it("returns true for a boxed integer equal to another boxed integer", () => {
      const left = Type.integer(1);
      const right = Type.integer(1);
      const result = Interpreter.isEqual(left, right);

      assert.isTrue(result);
    });

    // integer != integer
    it("returns false for a boxed integer not equal to another boxed integer", () => {
      const left = Type.integer(1);
      const right = Type.integer(2);
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // integer == float
    it("returns true for a boxed integer equal to a boxed float", () => {
      const left = Type.integer(1);
      const right = Type.float(1.0);
      const result = Interpreter.isEqual(left, right);

      assert.isTrue(result);
    });

    // integer != float
    it("returns false for a boxed integer not equal to a boxed float", () => {
      const left = Type.integer(1);
      const right = Type.float(2.0);
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // integer != non-number
    it("returns false when a boxed integer is compared to a boxed value of non-number type", () => {
      const left = Type.integer(1);
      const right = Type.bitstring("1");
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // float == float
    it("returns true for a boxed float equal to another boxed float", () => {
      const left = Type.float(1.0);
      const right = Type.float(1.0);
      const result = Interpreter.isEqual(left, right);

      assert.isTrue(result);
    });

    // float != float
    it("returns false for a boxed float not equal to another boxed float", () => {
      const left = Type.float(1.0);
      const right = Type.float(2.0);
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // float == integer
    it("returns true for a boxed float equal to a boxed integer", () => {
      const left = Type.float(1.0);
      const right = Type.integer(1);
      const result = Interpreter.isEqual(left, right);

      assert.isTrue(result);
    });

    // float != integer
    it("returns false for a boxed float not equal to a boxed integer", () => {
      const left = Type.float(1.0);
      const right = Type.integer(2);
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });

    // float != non-number
    it("returns false when a boxed float is compared to a boxed value of non-number type", () => {
      const left = Type.float(1.0);
      const right = Type.bitstring("1.0");
      const result = Interpreter.isEqual(left, right);

      assert.isFalse(result);
    });
  });

  describe("isMatched()", () => {
    let context;

    beforeEach(() => {
      context = contextFixture();
    });

    it("is matched", () => {
      assert.isTrue(
        Interpreter.isMatched(Type.integer(1), Type.integer(1), context),
      );
    });

    it("is not matched", () => {
      assert.isFalse(
        Interpreter.isMatched(Type.integer(1), Type.integer(2), context),
      );
    });

    it("adds matched vars to __matched__ field", () => {
      const result = Interpreter.isMatched(
        Type.variablePattern("x"),
        Type.integer(9),
        context,
      );

      assert.isTrue(result);
      assert.deepStrictEqual(context.vars, {__matched__: {x: Type.integer(9)}});
    });
  });

  describe("isStrictlyEqual()", () => {
    const isStrictlyEqual = Interpreter.isStrictlyEqual;

    describe("atoms", () => {
      it("equal", () => {
        const atom1 = Type.atom("abc");
        const atom2 = Type.atom("abc");

        assert.isTrue(isStrictlyEqual(atom1, atom2));
      });

      it("not equal", () => {
        const atom1 = Type.atom("abc");
        const atom2 = Type.atom("xyz");

        assert.isFalse(isStrictlyEqual(atom1, atom2));
      });
    });

    describe("bitstrings", () => {
      describe("equal", () => {
        it("both have text field", () => {
          const left = Type.bitstring("abc");
          const right = Type.bitstring("abc");

          assert.isTrue(Interpreter.isStrictlyEqual(left, right));
        });

        it("both have bytes field", () => {
          const left = Bitstring.fromBytes([97, 98, 99]);
          const right = Bitstring.fromBytes([97, 98, 99]);

          assert.isTrue(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has text field, right has bytes field", () => {
          const left = Type.bitstring("abc");
          const right = Bitstring.fromBytes([97, 98, 99]);

          assert.isTrue(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has bytes field, right has text field", () => {
          const left = Bitstring.fromBytes([97, 98, 99]);
          const right = Type.bitstring("abc");

          assert.isTrue(Interpreter.isStrictlyEqual(left, right));
        });
      });

      describe("not equal - different length", () => {
        it("both have text field", () => {
          const left = Type.bitstring("abc");
          const right = Type.bitstring("ab");

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("both have bytes field", () => {
          const left = Bitstring.fromBytes([97, 98, 99]);
          const right = Bitstring.fromBytes([97, 98]);

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has text field, right has bytes field", () => {
          const left = Type.bitstring("abc");
          const right = Bitstring.fromBytes([97, 98]);

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has bytes field, right has text field", () => {
          const left = Bitstring.fromBytes([97, 98]);
          const right = Type.bitstring("abc");

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });
      });

      describe("not equal - different content", () => {
        it("both have text field", () => {
          const left = Type.bitstring("abc");
          const right = Type.bitstring("xyz");

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("both have bytes field", () => {
          const left = Bitstring.fromBytes([97, 98, 99]);
          const right = Bitstring.fromBytes([97, 98, 100]);

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has text field, right has bytes field", () => {
          const left = Type.bitstring("abc");
          const right = Bitstring.fromBytes([97, 98, 100]);

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("left has bytes field, right has text field", () => {
          const left = Bitstring.fromBytes([97, 98, 100]);
          const right = Type.bitstring("abc");

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });

        it("leftover bits count is different", () => {
          const left = Bitstring.fromBytes([97, 98, 99]);
          left.leftoverBitCount = 2;

          const right = Bitstring.fromBytes([97, 98, 99]);
          right.leftoverBitCount = 3;

          assert.isFalse(Interpreter.isStrictlyEqual(left, right));
        });
      });
    });

    describe("floats", () => {
      it("equal", () => {
        const float1 = Type.float(1.23);
        const float2 = Type.float(1.23);

        assert.isTrue(isStrictlyEqual(float1, float2));
      });

      it("not equal", () => {
        const float1 = Type.float(1.23);
        const float2 = Type.float(2.34);

        assert.isFalse(isStrictlyEqual(float1, float2));
      });
    });

    describe("functions", () => {
      const dummyClauses = ["clause_dummy_1", "clause_dummy_2"];
      const context = contextFixture({});

      describe("captures", () => {
        it("equal", () => {
          const function1 = Type.functionCapture(
            "MyModule",
            "my_function",
            3,
            dummyClauses,
            context,
          );

          const function2 = Type.functionCapture(
            "MyModule",
            "my_function",
            3,
            dummyClauses,
            context,
          );

          assert.isTrue(isStrictlyEqual(function1, function2));
        });

        describe("not equal", () => {
          it("different module", () => {
            const function1 = Type.functionCapture(
              "MyModule1",
              "my_function",
              3,
              dummyClauses,
              context,
            );

            const function2 = Type.functionCapture(
              "MyModule2",
              "my_function",
              3,
              dummyClauses,
              context,
            );

            assert.isFalse(isStrictlyEqual(function1, function2));
          });

          it("different function", () => {
            const function1 = Type.functionCapture(
              "MyModule",
              "my_function_1",
              3,
              dummyClauses,
              context,
            );

            const function2 = Type.functionCapture(
              "MyModule",
              "my_function_2",
              3,
              dummyClauses,
              context,
            );

            assert.isFalse(isStrictlyEqual(function1, function2));
          });

          it("different arity", () => {
            const function1 = Type.functionCapture(
              "MyModule",
              "my_function",
              3,
              dummyClauses,
              context,
            );

            const function2 = Type.functionCapture(
              "MyModule",
              "my_function",
              4,
              dummyClauses,
              context,
            );

            assert.isFalse(isStrictlyEqual(function1, function2));
          });
        });
      });

      it("not captures", () => {
        const function1 = Type.anonymousFunction(3, dummyClauses, context);
        const function2 = structuredClone(function1);

        assert.isFalse(isStrictlyEqual(function1, function2));
      });
    });

    describe("integers", () => {
      it("equal", () => {
        const integer1 = Type.integer(123);
        const integer2 = Type.integer(123);

        assert.isTrue(isStrictlyEqual(integer1, integer2));
      });

      it("not equal", () => {
        const integer1 = Type.integer(123);
        const integer2 = Type.integer(234);

        assert.isFalse(isStrictlyEqual(integer1, integer2));
      });
    });

    describe("lists", () => {
      it("equal", () => {
        const list1 = Type.list([Type.integer(1), Type.float(2.34)]);
        const list2 = Type.list([Type.integer(1), Type.float(2.34)]);

        assert.isTrue(isStrictlyEqual(list1, list2));
      });

      it("not equal", () => {
        const list1 = Type.list([Type.integer(1), Type.float(2.34)]);
        const list2 = Type.list([Type.integer(1), Type.float(3.45)]);

        assert.isFalse(isStrictlyEqual(list1, list2));
      });
    });

    describe("maps", () => {
      it("equal", () => {
        const map1 = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.bitstring("b"), Type.float(2.34)],
        ]);

        const map2 = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.bitstring("b"), Type.float(2.34)],
        ]);

        assert.isTrue(isStrictlyEqual(map1, map2));
      });

      it("not equal", () => {
        const map1 = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.bitstring("b"), Type.float(2.34)],
        ]);

        const map2 = Type.map([
          [Type.atom("a"), Type.integer(1)],
          [Type.bitstring("b"), Type.float(3.45)],
        ]);

        assert.isFalse(isStrictlyEqual(map1, map2));
      });
    });

    describe("PIDs", () => {
      it("equal", () => {
        const pid1 = Type.pid("my_node", [0, 11, 222], "server");
        const pid2 = Type.pid("my_node", [0, 11, 222], "server");

        assert.isTrue(isStrictlyEqual(pid1, pid2));
      });

      describe("not equal", () => {
        it("different node", () => {
          const pid1 = Type.pid("my_node_1", [0, 11, 222], "server");
          const pid2 = Type.pid("my_node_2", [0, 11, 222], "server");

          assert.isFalse(isStrictlyEqual(pid1, pid2));
        });

        it("different segments", () => {
          const pid1 = Type.pid("my_node", [0, 11, 222], "server");
          const pid2 = Type.pid("my_node", [0, 11, 333], "server");

          assert.isFalse(isStrictlyEqual(pid1, pid2));
        });

        it("different origin", () => {
          const pid1 = Type.pid("my_node", [0, 11, 222], "server");
          const pid2 = Type.pid("my_node", [0, 11, 222], "client");

          assert.isFalse(isStrictlyEqual(pid1, pid2));
        });
      });
    });

    describe("ports", () => {
      it("equal", () => {
        const port1 = Type.port("my_node", [0, 11], "server");
        const port2 = Type.port("my_node", [0, 11], "server");

        assert.isTrue(isStrictlyEqual(port1, port2));
      });

      describe("not equal", () => {
        it("different node", () => {
          const port1 = Type.port("my_node_1", [0, 11], "server");
          const port2 = Type.port("my_node_2", [0, 11], "server");

          assert.isFalse(isStrictlyEqual(port1, port2));
        });

        it("different segments", () => {
          const port1 = Type.port("my_node", [0, 11], "server");
          const port2 = Type.port("my_node", [0, 22], "server");

          assert.isFalse(isStrictlyEqual(port1, port2));
        });

        it("different origin", () => {
          const port1 = Type.port("my_node", [0, 11], "server");
          const port2 = Type.port("my_node", [0, 11], "client");

          assert.isFalse(isStrictlyEqual(port1, port2));
        });
      });
    });

    describe("references", () => {
      it("equal", () => {
        const ref1 = Type.reference("my_node", 0, [3, 2, 1]);
        const ref2 = Type.reference("my_node", 0, [3, 2, 1]);

        assert.isTrue(isStrictlyEqual(ref1, ref2));
      });

      describe("not equal", () => {
        it("different node", () => {
          const ref1 = Type.reference("my_node_1", 0, [3, 2, 1]);
          const ref2 = Type.reference("my_node_2", 0, [3, 2, 1]);

          assert.isFalse(isStrictlyEqual(ref1, ref2));
        });

        it("different creation number", () => {
          const ref1 = Type.reference("my_node", 0, [3, 2, 1]);
          const ref2 = Type.reference("my_node", 4, [3, 2, 1]);

          assert.isFalse(isStrictlyEqual(ref1, ref2));
        });

        it("different ID word 1", () => {
          const ref1 = Type.reference("my_node", 0, [3, 2, 1]);
          const ref2 = Type.reference("my_node", 0, [4, 2, 1]);

          assert.isFalse(isStrictlyEqual(ref1, ref2));
        });

        it("different ID word 2", () => {
          const ref1 = Type.reference("my_node", 0, [3, 2, 1]);
          const ref2 = Type.reference("my_node", 0, [3, 4, 1]);

          assert.isFalse(isStrictlyEqual(ref1, ref2));
        });

        it("different ID word 3", () => {
          const ref1 = Type.reference("my_node", 0, [3, 2, 1]);
          const ref2 = Type.reference("my_node", 0, [3, 2, 4]);

          assert.isFalse(isStrictlyEqual(ref1, ref2));
        });
      });
    });

    describe("tuples", () => {
      it("equal", () => {
        const tuple1 = Type.tuple([Type.integer(1), Type.float(2.34)]);
        const tuple2 = Type.tuple([Type.integer(1), Type.float(2.34)]);

        assert.isTrue(isStrictlyEqual(tuple1, tuple2));
      });

      it("not equal", () => {
        const tuple1 = Type.tuple([Type.integer(1), Type.float(2.34)]);
        const tuple2 = Type.tuple([Type.integer(1), Type.float(3.45)]);

        assert.isFalse(isStrictlyEqual(tuple1, tuple2));
      });
    });

    it("equal but not strictly equal", () => {
      assert.isFalse(isStrictlyEqual(Type.integer(1), Type.float(1.0)));
    });
  });

  // IMPORTANT!
  // Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/match_operator_test.exs
  // Always update both together.
  //
  // left and right args are not stored in temporary variables but used directly in matchOperator() call,
  // to make the test as close as possible to real behaviour in which the matchOperator() call is encoded as a whole.
  describe("matchOperator()", () => {
    const varsWithEmptyMatchedValues = {a: Type.integer(9), __matched__: {}};

    let context;

    beforeEach(() => {
      context = contextFixture({vars: {a: Type.integer(9)}});
    });

    describe("atom type", () => {
      // :abc = :abc
      it("left atom == right atom", () => {
        const result = Interpreter.matchOperator(
          Type.atom("abc"),
          Type.atom("abc"),
          context,
        );

        assert.deepStrictEqual(result, Type.atom("abc"));
        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // :abc = :xyz
      it("left atom != right atom", () => {
        const myAtom = Type.atom("xyz");

        assertBoxedError(
          () => Interpreter.matchOperator(myAtom, Type.atom("abc"), context),
          "MatchError",
          "no match of right hand side value: :xyz",
        );
      });

      // :abc = 2
      it("left atom != right non-atom", () => {
        const myInteger = Type.integer(2);

        assertBoxedError(
          () => Interpreter.matchOperator(myInteger, Type.atom("abc"), context),
          "MatchError",
          "no match of right hand side value: 2",
        );
      });
    });

    describe("bitstring type", () => {
      const emptyBitstringPattern = Type.bitstringPattern([]);
      const emptyBitstringValue = Type.bitstring([]);

      const multiSegmentBitstringValue = Type.bitstring([
        Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        Type.bitstringSegment(Type.integer(2), {type: "integer"}),
      ]);

      // <<>> = <<>>
      it("left empty bitstring == right empty bitstring", () => {
        const result = Interpreter.matchOperator(
          emptyBitstringValue,
          emptyBitstringPattern,
          context,
        );

        assertBoxedStrictEqual(result, emptyBitstringValue);
      });

      // <<>> = <<1::1, 0::1>>
      it("left empty bitstring != right non-empty bitstring", () => {
        const myBitstring = Type.bitstring([1, 0]);

        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              myBitstring,
              emptyBitstringPattern,
              context,
            ),
          "MatchError",
          "no match of right hand side value: <<2::size(2)>>",
        );
      });

      // <<>> = :abc
      it("left empty bitstring != right non-bitstring", () => {
        const myAtom = Type.atom("abc");

        assertBoxedError(
          () =>
            Interpreter.matchOperator(myAtom, emptyBitstringPattern, context),
          "MatchError",
          "no match of right hand side value: :abc",
        );
      });

      it("left literal single-segment bitstring == right literal single-segment bitstring", () => {
        const result = Interpreter.matchOperator(
          Type.bitstring([
            Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          ]),
          Type.bitstringPattern([
            Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          ]),
          context,
        );

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        assertBoxedStrictEqual(result, expected);
      });

      it("left literal single-segment bitstring != right literal single-segment bitstring", () => {
        const myBitstring = Type.bitstring([
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              myBitstring,
              Type.bitstringPattern([
                Type.bitstringSegment(Type.integer(1), {type: "integer"}),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: <<2>>",
        );
      });

      it("left literal single-segment bitstring != right non-bitstring", () => {
        const myAtom = Type.atom("abc");

        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              myAtom,
              Type.bitstringPattern([
                Type.bitstringSegment(Type.integer(1), {type: "integer"}),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: :abc",
        );
      });

      it("multiple literal bitstring segments", () => {
        const result = Interpreter.matchOperator(
          Type.bitstring([
            Type.bitstringSegment(Type.integer(1), {
              type: "integer",
              size: Type.integer(1),
            }),
            Type.bitstringSegment(Type.integer(0), {
              type: "integer",
              size: Type.integer(1),
            }),
          ]),
          Type.bitstringPattern([
            Type.bitstringSegment(Type.integer(1), {
              type: "integer",
              size: Type.integer(1),
            }),
            Type.bitstringSegment(Type.integer(0), {
              type: "integer",
              size: Type.integer(1),
            }),
          ]),
          context,
        );

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {
            type: "integer",
            size: Type.integer(1),
          }),
          Type.bitstringSegment(Type.integer(0), {
            type: "integer",
            size: Type.integer(1),
          }),
        ]);

        assertBoxedStrictEqual(result, expected);
      });

      it("multiple literal float segments", () => {
        const result = Interpreter.matchOperator(
          Type.bitstring([
            Type.bitstringSegment(Type.float(1.0), {type: "float"}),
            Type.bitstringSegment(Type.float(2.0), {type: "float"}),
          ]),
          Type.bitstringPattern([
            Type.bitstringSegment(Type.float(1.0), {type: "float"}),
            Type.bitstringSegment(Type.float(2.0), {type: "float"}),
          ]),
          context,
        );

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.float(1.0), {type: "float"}),
          Type.bitstringSegment(Type.float(2.0), {type: "float"}),
        ]);

        assertBoxedStrictEqual(result, expected);
      });

      it("multiple literal integer segments", () => {
        const result = Interpreter.matchOperator(
          Type.bitstring([
            Type.bitstringSegment(Type.integer(1), {type: "integer"}),
            Type.bitstringSegment(Type.integer(2), {type: "integer"}),
          ]),
          Type.bitstringPattern([
            Type.bitstringSegment(Type.integer(1), {type: "integer"}),
            Type.bitstringSegment(Type.integer(2), {type: "integer"}),
          ]),
          context,
        );

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]);

        assertBoxedStrictEqual(result, expected);
      });

      it("multiple literal string segments", () => {
        const result = Interpreter.matchOperator(
          Type.bitstring([
            Type.bitstringSegment(Type.string("aaa"), {type: "binary"}),
            Type.bitstringSegment(Type.string("bbb"), {type: "binary"}),
          ]),
          Type.bitstringPattern([
            Type.bitstringSegment(Type.string("aaa"), {type: "binary"}),
            Type.bitstringSegment(Type.string("bbb"), {type: "binary"}),
          ]),
          context,
        );

        const expected = Type.bitstring([
          Type.bitstringSegment(Type.string("aaa"), {type: "binary"}),
          Type.bitstringSegment(Type.string("bbb"), {type: "binary"}),
        ]);

        assertBoxedStrictEqual(result, expected);
      });

      // <<x::integer>> = <<1>>
      it("left single-segment bitstring with variable pattern == right bitstring", () => {
        const myBitstring = Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]);

        const result = Interpreter.matchOperator(
          myBitstring,
          Type.bitstringPattern([
            Type.bitstringSegment(Type.variablePattern("x"), {type: "integer"}),
          ]),
          context,
        );

        assertBoxedStrictEqual(result, myBitstring);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
          },
        });
      });

      // <<x::integer, y::integer>> = <<1, 2>>
      it("left multiple-segment bitstring with variable patterns == right bitstring", () => {
        const result = Interpreter.matchOperator(
          multiSegmentBitstringValue,
          Type.bitstringPattern([
            Type.bitstringSegment(Type.variablePattern("x"), {type: "integer"}),
            Type.bitstringSegment(Type.variablePattern("y"), {type: "integer"}),
          ]),
          context,
        );

        assertBoxedStrictEqual(result, multiSegmentBitstringValue);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(2),
          },
        });
      });

      // <<3, y::integer>> = <<1, 2>>
      it("first segment in left multi-segment bitstring doesn't match", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              multiSegmentBitstringValue,
              Type.bitstringPattern([
                Type.bitstringSegment(Type.integer(3), {type: "integer"}),
                Type.bitstringSegment(Type.variablePattern("y"), {
                  type: "integer",
                }),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: <<1, 2>>",
        );
      });

      // <<1, 2::size(7)>> = <<1, 2>>
      it("last segment in left multi-segment bitstring doesn't match, because there are too few bits", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              multiSegmentBitstringValue,
              Type.bitstringPattern([
                Type.bitstringSegment(Type.integer(1), {type: "integer"}),
                Type.bitstringSegment(Type.integer(2), {
                  type: "integer",
                  size: Type.integer(7),
                }),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: <<1, 2>>",
        );
      });

      // <<1, 2::size(9)>> = <<1, 2>>
      it("last segment in left multi-segment bitstring doesn't match, because there are too many bits", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              multiSegmentBitstringValue,
              Type.bitstringPattern([
                Type.bitstringSegment(Type.integer(1), {type: "integer"}),
                Type.bitstringSegment(Type.integer(2), {
                  type: "integer",
                  size: Type.integer(9),
                }),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: <<1, 2>>",
        );
      });

      describe("last segment matching", () => {
        // <<prefix::size(8), rest::binary>> = "hello"
        it("last binary segment without size consumes all remaining bits", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "binary",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("ello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(8), rest::bitstring>> = "hello"
        it("last bitstring segment without size consumes all remaining bits", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("ello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(12), rest::bitstring>> = <<1, 2, 3>>
        it("last bitstring segment without size consumes remaining bits even when not byte-aligned", () => {
          const myBitstring = Type.bitstring([
            Type.bitstringSegment(Type.integer(1), {type: "integer"}),
            Type.bitstringSegment(Type.integer(2), {type: "integer"}),
            Type.bitstringSegment(Type.integer(3), {type: "integer"}),
          ]);

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(12),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring([
              Type.bitstringSegment(Type.integer(32), {type: "integer"}),
              Type.bitstringSegment(Type.integer(3), {
                type: "integer",
                size: Type.integer(4),
              }),
            ]),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(16),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(8), rest::binary>> = "h"
        it("last binary segment without size handles empty remaining bits", () => {
          const myBitstring = Type.bitstring("h");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "binary",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring(""),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(8), rest::bitstring>> = "h"
        it("last bitstring segment without size handles empty remaining bits", () => {
          const myBitstring = Type.bitstring("h");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring(""),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<rest::binary>> = "hello"
        it("single last binary segment without size consumes entire bitstring", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "binary",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("hello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<rest::bitstring>> = "hello"
        it("single last bitstring segment without size consumes entire bitstring", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("hello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<rest::bitstring>> = <<1::1, 0::1, 1::1>>
        it("single last bitstring segment without size consumes entire non-byte-aligned bitstring", () => {
          const myBitstring = Type.bitstring([1, 0, 1]);

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(context.vars.__matched__.rest, myBitstring);

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<rest::binary>> = ""
        it("single last binary segment without size consumes empty bitstring", () => {
          const myBitstring = Type.bitstring("");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "binary",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring(""),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<rest::bitstring>> = ""
        it("single last bitstring segment without size consumes empty bitstring", () => {
          const myBitstring = Type.bitstring("");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring(""),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // This won't compile
        // <<first::binary, second::size(8)>> = "hello"
        // it("non-last binary segment without size fails normally")

        // This won't compile
        // <<first::bitstring, second::size(8)>> = "hello"
        // it("non-last bitstring segment without size fails normally")

        // <<prefix::size(8), rest::binary-size(4)>> = "hello"
        it("last binary segment with explicit size uses normal size calculation", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "binary",
                size: Type.integer(4),
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("ello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(8), rest::bitstring-size(4 * 8)>> = "hello"
        it("last bitstring segment with explicit size uses normal size calculation", () => {
          const myBitstring = Type.bitstring("hello");

          const result = Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.variablePattern("prefix"), {
                type: "integer",
                size: Type.integer(8),
              }),
              Type.bitstringSegment(Type.variablePattern("rest"), {
                type: "bitstring",
                size: Type.integer(4 * 8),
              }),
            ]),
            context,
          );

          assertBoxedStrictEqual(result, myBitstring);

          assertBoxedStrictEqual(
            context.vars.__matched__.rest,
            Type.bitstring("ello"),
          );

          assert.deepStrictEqual(context.vars, {
            a: Type.integer(9),
            __matched__: {
              prefix: Type.integer(104),
              rest: context.vars.__matched__.rest,
            },
          });
        });

        // <<prefix::size(8), rest::binary-size(40)>> = "hello"
        it("last binary segment with size larger than remaining bits fails", () => {
          const myBitstring = Type.bitstring("hello");

          assertBoxedError(
            () =>
              Interpreter.matchOperator(
                myBitstring,
                Type.bitstringPattern([
                  Type.bitstringSegment(Type.variablePattern("prefix"), {
                    type: "integer",
                    size: Type.integer(8),
                  }),
                  Type.bitstringSegment(Type.variablePattern("rest"), {
                    type: "binary",
                    size: Type.integer(40),
                  }),
                ]),
                context,
              ),
            "MatchError",
            'no match of right hand side value: "hello"',
          );
        });

        // <<prefix::size(8), rest::bitstring-size(40)>> = "hello"
        it("last bitstring segment with size larger than remaining bits fails", () => {
          const myBitstring = Type.bitstring("hello");

          assertBoxedError(
            () =>
              Interpreter.matchOperator(
                myBitstring,
                Type.bitstringPattern([
                  Type.bitstringSegment(Type.variablePattern("prefix"), {
                    type: "integer",
                    size: Type.integer(8),
                  }),
                  Type.bitstringSegment(Type.variablePattern("rest"), {
                    type: "bitstring",
                    size: Type.integer(40),
                  }),
                ]),
                context,
              ),
            "MatchError",
            'no match of right hand side value: "hello"',
          );
        });

        // <<prefix::size(8), rest::integer>> = "hello"
        it("last integer segment without size uses normal size calculation and fails due to leftover bits", () => {
          const myBitstring = Type.bitstring("hello");

          assertBoxedError(
            () =>
              Interpreter.matchOperator(
                myBitstring,
                Type.bitstringPattern([
                  Type.bitstringSegment(Type.variablePattern("prefix"), {
                    type: "integer",
                    size: Type.integer(8),
                  }),
                  Type.bitstringSegment(Type.variablePattern("rest"), {
                    type: "integer",
                  }),
                ]),
                context,
              ),
            "MatchError",
            'no match of right hand side value: "hello"',
          );
        });
      });
    });

    describe("bitstring segment decoding, signed modifier", () => {
      // <<value::signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      // The test would be the same as "integer type modifier", because the encoder always specifies the segment's type.
      // it("no type modifier")

      // <<value::binary-signed>> won't compile
      // it("binary type modifier")

      // <<value::bitstring-signed>> won't compile
      // it("bitstring type modifier")

      // <<value::float-size(64)-signed>> = <<123.45::size(64)>>
      it("float type modifier, 64-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(64),
            signedness: "signed",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(64),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.45)},
        });
      });

      // <<value::float-size(32)-signed>> = <<123.45::size(32)>>
      it("float type modifier, 32-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(32),
            signedness: "signed",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(32),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.44999694824219)},
        });
      });

      // <<value::float-size(16)-signed>> = <<123.45::size(16)>>
      it("float type modifier, 16-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(16),
            signedness: "signed",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(16),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.4375)},
        });
      });

      // <<_value::float-size(size)-signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      it("float type modifier, unsupported size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(8),
            signedness: "signed",
          }),
        ]);

        // 170 == 0b10101010
        const right = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]);

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: <<170>>",
        );
      });

      // <<value::integer-signed>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      it("integer type modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "integer",
            signedness: "signed",
          }),
        ]);

        // 170 == 0b10101010
        const right = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.integer(-86)},
        });
      });

      // <value::utf8-signed>> won't compile
      // it("utf8 type modifier")

      // <value::utf16-signed>> won't compile
      // it("utf16 type modifier")

      // <value::utf32-signed>> won't compile
      // it("utf32 type modifier")
    });

    describe("bitstring segment decoding, unsigned modifier", () => {
      // <<value::unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      // The test would be the same as "integer type modifier", because the encoder always specifies the segment's type.
      // it("no type modifier")

      // <<value::binary-unsigned>> won't compile
      // it("binary type modifier")

      // <<value::bitstring-unsigned>> won't compile
      // it("bitstring type modifier")

      // <<value::float-size(64)-unsigned>> = <<123.45::size(64)>>
      it("float type modifier, 64-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(64),
            signedness: "unsigned",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(64),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.45)},
        });
      });

      // <<value::float-size(32)-unsigned>> = <<123.45::size(32)>>
      it("float type modifier, 32-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(32),
            signedness: "unsigned",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(32),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.44999694824219)},
        });
      });

      // <<value::float-size(16)-unsigned>> = <<123.45::size(16)>>
      it("float type modifier, 16-bit size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(16),
            signedness: "unsigned",
          }),
        ]);

        const right = Type.bitstring([
          Type.bitstringSegment(Type.float(123.45), {
            type: "float",
            size: Type.integer(16),
          }),
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.float(123.4375)},
        });
      });

      // <<_value::float-size(size)-unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      it("float type modifier, unsupported size modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "float",
            size: Type.integer(8),
            signedness: "unsigned",
          }),
        ]);

        // 170 == 0b10101010
        const right = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]);

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: <<170>>",
        );
      });

      // <<value::integer-unsigned>> = <<1::1, 0::1, 1::1, 0::1, 1::1, 0::1, 1::1, 0::1>>
      it("integer type modifier", () => {
        const left = Type.bitstringPattern([
          Type.bitstringSegment(Type.variablePattern("value"), {
            type: "integer",
            signedness: "unsigned",
          }),
        ]);

        // 170 == 0b10101010
        const right = Type.bitstring([1, 0, 1, 0, 1, 0, 1, 0]);

        const result = Interpreter.matchOperator(right, left, context);

        assertBoxedStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {value: Type.integer(170)},
        });
      });

      // <value::utf8-unsigned>> won't compile
      // it("utf8 type modifier")

      // <value::utf16-unsigned>> won't compile
      // it("utf16 type modifier")

      // <value::utf32-unsigned>> won't compile
      // it("utf32 type modifier")
    });

    // TODO: finish overhaul, remember about Elixir consistency tests
    // describe("cons pattern", () => {
    //   describe("[h | t]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.variablePattern("t"),
    //       );
    //     });
    //     it("[h | t] = 1", () => {
    //       const right = Type.integer(1);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | t] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | t] = [1]", () => {
    //       const right = Type.list([Type.integer(1)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //         t: Type.list(),
    //       });
    //     });
    //     it("[h | t] = [1, 2]", () => {
    //       const right = Type.list([Type.integer(1), Type.integer(2)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //         t: Type.list([Type.integer(2)]),
    //       });
    //     });
    //     it("[h | t] = [1 | 2]", () => {
    //       const right = Type.improperList([Type.integer(1), Type.integer(2)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //         t: Type.integer(2),
    //       });
    //     });
    //     it("[h | t] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //         t: Type.list([Type.integer(2), Type.integer(3)]),
    //       });
    //     });
    //     it("[h | t] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //         t: Type.improperList([Type.integer(2), Type.integer(3)]),
    //       });
    //     });
    //   });
    //   describe("[1 | t]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(Type.integer(1), Type.variablePattern("t"));
    //     });
    //     it("[1 | t] = 1", () => {
    //       const right = Type.integer(1);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = [1]", () => {
    //       const right = Type.list([Type.integer(1)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         t: Type.list(),
    //       });
    //     });
    //     it("[1 | t] = [5]", () => {
    //       const right = Type.list([Type.integer(5)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = [1, 2]", () => {
    //       const right = Type.list([Type.integer(1), Type.integer(2)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         t: Type.list([Type.integer(2)]),
    //       });
    //     });
    //     it("[1 | t] = [5, 2]", () => {
    //       const right = Type.list([Type.integer(5), Type.integer(2)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = [1 | 2]", () => {
    //       const right = Type.improperList([Type.integer(1), Type.integer(2)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         t: Type.integer(2),
    //       });
    //     });
    //     it("[1 | t] = [5 | 2]", () => {
    //       const right = Type.improperList([Type.integer(5), Type.integer(2)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         t: Type.list([Type.integer(2), Type.integer(3)]),
    //       });
    //     });
    //     it("[1 | t] = [5, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(5),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | t] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         t: Type.improperList([Type.integer(2), Type.integer(3)]),
    //       });
    //     });
    //     it("[1 | t] = [5, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(5),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | 3]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(Type.variablePattern("h"), Type.integer(3));
    //     });
    //     it("[h | 3] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | 3] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | 3] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | 3] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | 3] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(2),
    //       });
    //     });
    //     it("[h | 3] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | 3] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | []]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(Type.variablePattern("h"), Type.list());
    //     });
    //     it("[h | []] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | []] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | []] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(3),
    //       });
    //     });
    //     it("[h | []] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | []] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | []] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | []] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | [3]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.list([Type.integer(3)]),
    //       );
    //     });
    //     it("[h | [3]] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [3]] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [3]] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [3]] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(2),
    //       });
    //     });
    //     it("[h | [3]] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [3]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [3]] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | [2, 3]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.list([Type.integer(2), Type.integer(3)]),
    //       );
    //     });
    //     it("[h | [2, 3]] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2, 3]] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2, 3]] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2, 3]] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2, 3]] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2, 3]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //       });
    //     });
    //     it("[h | [2, 3]] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | [2 | 3]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.consPattern(Type.integer(2), Type.integer(3)),
    //       );
    //     });
    //     it("[h | [2 | 3]] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [2 | 3]] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {
    //         a: Type.integer(9),
    //         h: Type.integer(1),
    //       });
    //     });
    //   });
    //   describe("[h | [1, 2, 3]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2, 3]] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[h | [1, 2 | 3]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.variablePattern("h"),
    //         Type.consPattern(
    //           Type.integer(1),
    //           Type.consPattern(Type.integer(2), Type.integer(3)),
    //         ),
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = 3", () => {
    //       const right = Type.integer(3);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = []", () => {
    //       const right = Type.list();
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = [3]", () => {
    //       const right = Type.list([Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = [2, 3]", () => {
    //       const right = Type.list([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = [2 | 3]", () => {
    //       const right = Type.improperList([Type.integer(2), Type.integer(3)]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[h | [1, 2 | 3]] = [1, 2 | 3]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[1 | [2 | [3 | []]]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.integer(1),
    //         Type.consPattern(
    //           Type.integer(2),
    //           Type.consPattern(Type.integer(3), Type.list()),
    //         ),
    //       );
    //     });
    //     it("[1 | [2 | [3 | []]]] = [1, 2, 3, 4]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | [2 | [3 | []]]] = [1, 2, 3 | 4]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | [2 | [3 | []]]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //     });
    //   });
    //   describe("[1 | [2 | [3 | 4]]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.integer(1),
    //         Type.consPattern(
    //           Type.integer(2),
    //           Type.consPattern(Type.integer(3), Type.integer(4)),
    //         ),
    //       );
    //     });
    //     it("[1 | [2 | [3 | 4]]] = [1, 2, 3, 4]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | [2 | [3 | 4]]] = [1, 2, 3 | 4]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //     });
    //     it("[1 | [2 | [3 | 4]]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    //   describe("[1 | [2 | [3 | [4]]]]", () => {
    //     let left;
    //     beforeEach(() => {
    //       left = Type.consPattern(
    //         Type.integer(1),
    //         Type.consPattern(
    //           Type.integer(2),
    //           Type.consPattern(Type.integer(3), Type.list([Type.integer(4)])),
    //         ),
    //       );
    //     });
    //     it("[1 | [2 | [3 | [4]]]] = [1, 2, 3, 4]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       const result = Interpreter.matchOperator(right, left, vars);
    //       assert.deepStrictEqual(result, right);
    //       assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //     });
    //     it("[1 | [2 | [3 | [4]]]] = [1, 2, 3 | 4]", () => {
    //       const right = Type.improperList([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //         Type.integer(4),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //     it("[1 | [2 | [3 | [4]]]] = [1, 2, 3]", () => {
    //       const right = Type.list([
    //         Type.integer(1),
    //         Type.integer(2),
    //         Type.integer(3),
    //       ]);
    //       assertMatchError(
    //         () => Interpreter.matchOperator(right, left, vars),
    //         right,
    //       );
    //     });
    //   });
    // });

    // TODO: finish overhaul, remember about Elixir consistency tests
    // describe("float type", () => {
    //   it("left float == right float", () => {
    //     // 2.0 = 2.0
    //     const result = Interpreter.matchOperator(
    //       Type.float(2.0),
    //       Type.float(2.0),
    //       vars,
    //     );
    //     assert.deepStrictEqual(result, Type.float(2.0));
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("left float != right float", () => {
    //     const myFloat = Type.float(3.0);
    //     // 2.0 = 3.0
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myFloat, Type.float(2.0), vars),
    //       myFloat,
    //     );
    //   });
    //   it("left float != right non-float", () => {
    //     const myAtom = Type.atom("abc");
    //     // 2.0 = :abc
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myAtom, Type.float(2.0), vars),
    //       myAtom,
    //     );
    //   });
    // });

    // TODO: finish overhaul, remember about Elixir consistency tests
    // describe("integer type", () => {
    //   it("left integer == right integer", () => {
    //     // 2 = 2
    //     const result = Interpreter.matchOperator(
    //       Type.integer(2),
    //       Type.integer(2),
    //       vars,
    //     );
    //     assert.deepStrictEqual(result, Type.integer(2));
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("left integer != right integer", () => {
    //     const myInteger = Type.integer(3);
    //     // 2 = 3
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myInteger, Type.integer(2), vars),
    //       myInteger,
    //     );
    //   });
    //   it("left integer != right non-integer", () => {
    //     const myAtom = Type.atom("abc");
    //     // 2 = :abc
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myAtom, Type.integer(2), vars),
    //       myAtom,
    //     );
    //   });
    // });

    // TODO: finish overhaul, remember about Elixir consistency tests
    // describe("list type", () => {
    //   let list1;
    //   beforeEach(() => {
    //     list1 = Type.list([Type.integer(1), Type.integer(2)]);
    //   });
    //   it("[1, 2] = [1, 2]", () => {
    //     const result = Interpreter.matchOperator(list1, list1, vars);
    //     assert.deepStrictEqual(result, list1);
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("[1, 2] = [1, 3]", () => {
    //     const list2 = Type.list([Type.integer(1), Type.integer(3)]);
    //     assertMatchError(
    //       () => Interpreter.matchOperator(list2, list1, vars),
    //       list2,
    //     );
    //   });
    //   it("[1, 2] = [1 | 2]", () => {
    //     const list2 = Type.improperList([Type.integer(1), Type.integer(2)]);
    //     assertMatchError(
    //       () => Interpreter.matchOperator(list2, list1, vars),
    //       list2,
    //     );
    //   });
    //   it("[1, 2] = :abc", () => {
    //     const myAtom = Type.atom("abc");
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myAtom, list1, vars),
    //       myAtom,
    //     );
    //   });
    //   it("[] = [1, 2]", () => {
    //     assertMatchError(
    //       () => Interpreter.matchOperator(list1, Type.list(), vars),
    //       list1,
    //     );
    //   });
    //   it("[1, 2] = []", () => {
    //     const emptyList = Type.list();
    //     assertMatchError(
    //       () => Interpreter.matchOperator(emptyList, list1, vars),
    //       emptyList,
    //     );
    //   });
    //   it("[] = []", () => {
    //     const emptyList = Type.list();
    //     const result = Interpreter.matchOperator(emptyList, emptyList, vars);
    //     assert.deepStrictEqual(result, emptyList);
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("[x, 2, y] = [1, 2, 3]", () => {
    //     const left = Type.list([
    //       Type.variablePattern("x"),
    //       Type.integer(2),
    //       Type.variablePattern("y"),
    //     ]);
    //     const right = Type.list([
    //       Type.integer(1),
    //       Type.integer(2),
    //       Type.integer(3),
    //     ]);
    //     const result = Interpreter.matchOperator(right, left, vars);
    //     assert.deepStrictEqual(result, right);
    //     const expectedVars = {
    //       a: Type.integer(9),
    //       x: Type.integer(1),
    //       y: Type.integer(3),
    //     };
    //     assert.deepStrictEqual(vars, expectedVars);
    //   });
    // });

    describe("map type", () => {
      const map = Type.map([
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
      ]);

      const emptyMap = Type.map();

      // %{x: 1, y: 2} = %{x: 1, y: 2}
      it("left and right maps have the same items", () => {
        const left = map;
        const right = structuredClone(map);
        const result = Interpreter.matchOperator(right, left, context);

        assert.deepStrictEqual(result, right);
        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // %{x: 1, y: 2} = %{x: 1, y: 2, z: 3}
      it("right map has all the same items as the left map plus additional ones", () => {
        const left = map;

        const right = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.atom("y"), Type.integer(2)],
          [Type.atom("z"), Type.integer(3)],
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assert.deepStrictEqual(result, right);
        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // %{x: 1, y: 2, z: 3} = %{x: 1, y: 2}
      // The error message on the client may have diffent map keys ordering (the map keys order in Elixir is unpredictable).
      it("right map is missing some some keys from the left map", () => {
        const left = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.atom("y"), Type.integer(2)],
          [Type.atom("z"), Type.integer(3)],
        ]);

        const right = map;

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: %{x: 1, y: 2}",
        );
      });

      // %{x: 1, y: 2} = %{x: 1, y: 3}
      // The error message on the client may have diffent map keys ordering (the map keys order in Elixir is unpredictable).
      it("some values in the left map don't match values in the right map", () => {
        const left = map;

        const right = Type.map([
          [Type.atom("x"), Type.integer(1)],
          [Type.atom("y"), Type.integer(3)],
        ]);

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: %{x: 1, y: 3}",
        );
      });

      // %{x: 1, y: 2} = :abc
      it("left map != right non-map", () => {
        const left = map;
        const right = Type.atom("abc");

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: :abc",
        );
      });

      // {k: x, m: 2, n: z} = %{k: 1, m: 2, n: 3}
      it("left map has variables", () => {
        const left = Type.map([
          [Type.atom("k"), Type.variablePattern("x")],
          [Type.atom("m"), Type.integer(2)],
          [Type.atom("n"), Type.variablePattern("z")],
        ]);

        const right = Type.map([
          [Type.atom("k"), Type.integer(1)],
          [Type.atom("m"), Type.integer(2)],
          [Type.atom("n"), Type.integer(3)],
        ]);

        const result = Interpreter.matchOperator(right, left, context);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            z: Type.integer(3),
          },
        });
      });

      // %{x: 1, y: 2} = %{}
      it("left is a non-empty map, right is an empty map", () => {
        const left = map;
        const right = emptyMap;

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: %{}",
        );
      });

      // %{} = %{x: 1, y: 2}
      it("left is an empty map, right is a non-empty map", () => {
        const left = emptyMap;
        const right = map;
        const result = Interpreter.matchOperator(right, left, context);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // %{} = %{}
      it("both left and right maps are empty", () => {
        const left = emptyMap;
        const right = emptyMap;
        const result = Interpreter.matchOperator(right, left, context);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });
    });

    describe("match placeholder", () => {
      // _var = 2
      it("integer", () => {
        const result = Interpreter.matchOperator(
          Type.integer(2),
          Type.matchPlaceholder(),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(2));

        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // :top = _placeholder
      it("atom with right placeholder", () => {
        const result = Interpreter.matchOperator(
          Type.matchPlaceholder(),
          Type.atom("top"),
          context,
        );

        assert.deepStrictEqual(result, Type.atom("top"));
        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      // <<prefix::size(8), _rest::binary>> = "hello"
      it("last bitstring segment", () => {
        const myBitstring = Type.bitstring("hello");

        const result = Interpreter.matchOperator(
          myBitstring,
          Type.bitstringPattern([
            Type.bitstringSegment(Type.variablePattern("prefix"), {
              type: "integer",
              size: Type.integer(8),
            }),
            Type.bitstringSegment(Type.matchPlaceholder(), {
              type: "binary",
            }),
          ]),
          context,
        );

        assertBoxedStrictEqual(result, myBitstring);

        // Match placeholder doesn't bind to variables, so prefix should be the only variable
        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            prefix: Type.integer(104),
          },
        });
      });

      // <<_prefix::size(8), rest::binary>> = "hello"
      it("non-last bitstring segment", () => {
        const myBitstring = Type.bitstring("hello");

        const result = Interpreter.matchOperator(
          myBitstring,
          Type.bitstringPattern([
            Type.bitstringSegment(Type.matchPlaceholder(), {
              type: "integer",
              size: Type.integer(8),
            }),
            Type.bitstringSegment(Type.variablePattern("rest"), {
              type: "binary",
            }),
          ]),
          context,
        );

        assertBoxedStrictEqual(result, myBitstring);

        assertBoxedStrictEqual(
          context.vars.__matched__.rest,
          Type.bitstring("ello"),
        );

        // Match placeholder doesn't bind to variables, so only rest should be bound
        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            rest: context.vars.__matched__.rest,
          },
        });
      });
    });

    describe("nested match operators", () => {
      it("x = 2 = 2", () => {
        const result = Interpreter.matchOperator(
          Interpreter.matchOperator(Type.integer(2), Type.integer(2), context),
          Type.variablePattern("x"),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(2));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(2),
          },
        });
      });

      it("x = 2 = 3", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.integer(3),
                Type.integer(2),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 3",
        );
      });

      it("2 = x = 2", () => {
        const result = Interpreter.matchOperator(
          Interpreter.matchOperator(
            Type.integer(2),
            Type.variablePattern("x"),
            context,
          ),
          Type.integer(2),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(2));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(2),
          },
        });
      });

      it("2 = x = 3", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.integer(3),
                Type.variablePattern("x"),
                context,
              ),
              Type.integer(2),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 3",
        );
      });

      it("2 = 2 = x, (x = 2)", () => {
        const context = contextFixture({
          vars: {
            a: Type.integer(9),
            x: Type.integer(2),
          },
        });

        const result = Interpreter.matchOperator(
          Interpreter.matchOperator(context.vars.x, Type.integer(2), context),
          Type.integer(2),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(2));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          x: Type.integer(2),
          __matched__: {},
        });
      });

      it("2 = 2 = x, (x = 3)", () => {
        const context = contextFixture({
          vars: {
            a: Type.integer(9),
            x: Type.integer(3),
          },
        });

        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                context.vars.x,
                Type.integer(2),
                context,
              ),
              Type.integer(2),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 3",
        );
      });

      it("1 = 2 = x, (x = 2)", () => {
        const context = contextFixture({
          vars: {
            a: Type.integer(9),
            x: Type.integer(2),
          },
        });

        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                context.vars.x,
                Type.integer(2),
                context,
              ),
              Type.integer(1),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 2",
        );
      });

      it("y = x + (x = 3) + x, (x = 11)", () => {
        const context = contextFixture({
          vars: {
            a: Type.integer(9),
            x: Type.integer(11),
          },
        });

        const result = Interpreter.matchOperator(
          Erlang["+/2"](
            Erlang["+/2"](
              context.vars.x,
              Interpreter.matchOperator(
                Type.integer(3),
                Type.variablePattern("x"),
                context,
              ),
            ),
            context.vars.x,
          ),
          Type.variablePattern("y"),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(25));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          x: Type.integer(11),
          __matched__: {
            x: Type.integer(3),
            y: Type.integer(25),
          },
        });
      });

      it("[1 = 1] = [1 = 1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([
            Interpreter.matchOperator(
              Type.integer(1),
              Type.integer(1),
              context,
            ),
          ]),
          Type.list([
            Interpreter.matchOperator(
              Type.integer(1),
              Type.integer(1),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
        assert.deepStrictEqual(context.vars, varsWithEmptyMatchedValues);
      });

      it("[1 = 1] = [1 = 2]", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(2),
                  Type.integer(1),
                  context,
                ),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(1),
                  context,
                ),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 2",
        );
      });

      it("[1 = 1] = [2 = 1]", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(2),
                  context,
                ),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(1),
                  context,
                ),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 1",
        );
      });

      // TODO: client error message for this case is inconsistent with server error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
      it("[1 = 2] = [1 = 1]", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(1),
                  context,
                ),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(2),
                  Type.integer(1),
                  context,
                ),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 2",
        );
      });

      // TODO: client error message for this case is inconsistent with server error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
      it("[2 = 1] = [1 = 1]", () => {
        assertBoxedError(
          () =>
            Interpreter.matchOperator(
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(1),
                  context,
                ),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.integer(2),
                  context,
                ),
              ]),
              context,
            ),
          "MatchError",
          "no match of right hand side value: 1",
        );
      });

      it("{a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}", () => {
        const context = contextFixture({
          vars: {
            a: Type.integer(9),
            f: Type.integer(3),
          },
        });

        const result = Interpreter.matchOperator(
          Interpreter.matchOperator(
            Type.tuple([
              Type.integer(1),
              Type.integer(2),
              Interpreter.matchOperator(
                context.vars.f,
                Type.variablePattern("e"),
                context,
              ),
            ]),
            Type.tuple([
              Type.integer(1),
              Interpreter.matchOperator(
                Type.variablePattern("d"),
                Type.variablePattern("c"),
                context,
              ),
              Type.integer(3),
            ]),
            context,
          ),
          Type.tuple([
            Interpreter.matchOperator(
              Type.variablePattern("b"),
              Type.variablePattern("a"),
              context,
            ),
            Type.integer(2),
            Type.integer(3),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.integer(1), Type.integer(2), Type.integer(3)]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          f: Type.integer(3),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(1),
            c: Type.integer(2),
            d: Type.integer(2),
            e: Type.integer(3),
          },
        });
      });
    });

    describe("nested match pattern (with uresolved variables)", () => {
      it("[[a | b] = [c | d]] = [[1, 2, 3]]", () => {
        const result = Interpreter.matchOperator(
          Type.list([
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          ]),
          Type.list([
            Interpreter.matchOperator(
              Type.consPattern(
                Type.variablePattern("c"),
                Type.variablePattern("d"),
              ),
              Type.consPattern(
                Type.variablePattern("a"),
                Type.variablePattern("b"),
              ),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.list([Type.integer(2), Type.integer(3)]),
            c: Type.integer(1),
            d: Type.list([Type.integer(2), Type.integer(3)]),
          },
        });
      });

      it("[[[a | b] = [c | d]] = [[e | f]]] = [[[1, 2, 3]]]", () => {
        const result = Interpreter.matchOperator(
          Type.list([
            Type.list([
              Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
            ]),
          ]),
          Type.list([
            Interpreter.matchOperator(
              Type.list([
                Type.consPattern(
                  Type.variablePattern("e"),
                  Type.variablePattern("f"),
                ),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.consPattern(
                    Type.variablePattern("c"),
                    Type.variablePattern("d"),
                  ),
                  Type.consPattern(
                    Type.variablePattern("a"),
                    Type.variablePattern("b"),
                  ),
                  context,
                ),
              ]),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([
              Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
            ]),
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.list([Type.integer(2), Type.integer(3)]),
            c: Type.integer(1),
            d: Type.list([Type.integer(2), Type.integer(3)]),
            e: Type.integer(1),
            f: Type.list([Type.integer(2), Type.integer(3)]),
          },
        });
      });

      it("[[a, b] = [c, d]] = [[1, 2]]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
          Type.list([
            Interpreter.matchOperator(
              Type.list([Type.variablePattern("c"), Type.variablePattern("d")]),
              Type.list([Type.variablePattern("a"), Type.variablePattern("b")]),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
          },
        });
      });

      it("[[[a, b] = [c, d]] = [[e, f]]] = [[[1, 2]]]", () => {
        const result = Interpreter.matchOperator(
          Type.list([
            Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
          ]),
          Type.list([
            Interpreter.matchOperator(
              Type.list([
                Type.list([
                  Type.variablePattern("e"),
                  Type.variablePattern("f"),
                ]),
              ]),
              Type.list([
                Interpreter.matchOperator(
                  Type.list([
                    Type.variablePattern("c"),
                    Type.variablePattern("d"),
                  ]),
                  Type.list([
                    Type.variablePattern("a"),
                    Type.variablePattern("b"),
                  ]),
                  context,
                ),
              ]),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.list([
            Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
            e: Type.integer(1),
            f: Type.integer(2),
          },
        });
      });

      it("[x = y] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Type.variablePattern("y"),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
          },
        });
      });

      it("[1 = x] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Type.variablePattern("x"),
              Type.integer(1),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
          },
        });
      });

      it("[x = 1] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Type.integer(1),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
          },
        });
      });

      it("[x = y = z] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.variablePattern("y"),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[1 = x = y] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("y"),
                Type.variablePattern("x"),
                context,
              ),
              Type.integer(1),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
          },
        });
      });

      it("[x = 1 = y] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("y"),
                Type.integer(1),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
          },
        });
      });

      it("[x = y = 1] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.integer(1),
                Type.variablePattern("y"),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
          },
        });
      });

      it("[v = x = y = z] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.variablePattern("z"),
                  Type.variablePattern("y"),
                  context,
                ),
                Type.variablePattern("x"),
                context,
              ),
              Type.variablePattern("v"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            v: Type.integer(1),
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[1 = x = y = z] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.variablePattern("z"),
                  Type.variablePattern("y"),
                  context,
                ),
                Type.variablePattern("x"),
                context,
              ),
              Type.integer(1),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[x = 1 = y = z] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.variablePattern("z"),
                  Type.variablePattern("y"),
                  context,
                ),
                Type.integer(1),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[x = y = 1 = z] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.variablePattern("z"),
                  Type.integer(1),
                  context,
                ),
                Type.variablePattern("y"),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[x = y = z = 1] = [1]", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1)]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.integer(1),
                  Type.variablePattern("z"),
                  context,
                ),
                Type.variablePattern("y"),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );
        assert.deepStrictEqual(result, Type.list([Type.integer(1)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
            y: Type.integer(1),
            z: Type.integer(1),
          },
        });
      });

      it("[x = y = z] = [a = b = c = 2]", () => {
        const result = Interpreter.matchOperator(
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Interpreter.matchOperator(
                  Type.integer(2),
                  Type.variablePattern("c"),
                  context,
                ),
                Type.variablePattern("b"),
                context,
              ),
              Type.variablePattern("a"),
              context,
            ),
          ]),
          Type.list([
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.variablePattern("y"),
                context,
              ),
              Type.variablePattern("x"),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(result, Type.list([Type.integer(2)]));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(2),
            b: Type.integer(2),
            c: Type.integer(2),
            x: Type.integer(2),
            y: Type.integer(2),
            z: Type.integer(2),
          },
        });
      });

      it("%{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: 1, b: 2}}", () => {
        const result = Interpreter.matchOperator(
          Type.map([
            [
              Type.atom("x"),
              Type.map([
                [Type.atom("a"), Type.integer(1)],
                [Type.atom("b"), Type.integer(2)],
              ]),
            ],
          ]),
          Type.map([
            [
              Type.atom("x"),
              Interpreter.matchOperator(
                Type.map([
                  [Type.atom("a"), Type.variablePattern("c")],
                  [Type.atom("b"), Type.variablePattern("d")],
                ]),
                Type.map([
                  [Type.atom("a"), Type.variablePattern("a")],
                  [Type.atom("b"), Type.variablePattern("b")],
                ]),
                context,
              ),
            ],
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.map([
            [
              Type.atom("x"),
              Type.map([
                [Type.atom("a"), Type.integer(1)],
                [Type.atom("b"), Type.integer(2)],
              ]),
            ],
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
          },
        });
      });

      it("%{y: %{x: %{a: a, b: b} = %{a: c, b: d}} = %{x: %{a: e, b: f}}} = %{y: %{x: %{a: 1, b: 2}}}", () => {
        const result = Interpreter.matchOperator(
          Type.map([
            [
              Type.atom("y"),
              Type.map([
                [
                  Type.atom("x"),
                  Type.map([
                    [Type.atom("a"), Type.integer(1)],
                    [Type.atom("b"), Type.integer(2)],
                  ]),
                ],
              ]),
            ],
          ]),
          Type.map([
            [
              Type.atom("y"),
              Interpreter.matchOperator(
                Type.map([
                  [
                    Type.atom("x"),
                    Type.map([
                      [Type.atom("a"), Type.variablePattern("e")],
                      [Type.atom("b"), Type.variablePattern("f")],
                    ]),
                  ],
                ]),
                Type.map([
                  [
                    Type.atom("x"),
                    Interpreter.matchOperator(
                      Type.map([
                        [Type.atom("a"), Type.variablePattern("c")],
                        [Type.atom("b"), Type.variablePattern("d")],
                      ]),
                      Type.map([
                        [Type.atom("a"), Type.variablePattern("a")],
                        [Type.atom("b"), Type.variablePattern("b")],
                      ]),
                      context,
                    ),
                  ],
                ]),
                context,
              ),
            ],
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.map([
            [
              Type.atom("y"),
              Type.map([
                [
                  Type.atom("x"),
                  Type.map([
                    [Type.atom("a"), Type.integer(1)],
                    [Type.atom("b"), Type.integer(2)],
                  ]),
                ],
              ]),
            ],
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
            e: Type.integer(1),
            f: Type.integer(2),
          },
        });
      });

      it("{{a, b} = {c, d}} = {{1, 2}}", () => {
        const result = Interpreter.matchOperator(
          Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
          Type.tuple([
            Interpreter.matchOperator(
              Type.tuple([
                Type.variablePattern("c"),
                Type.variablePattern("d"),
              ]),
              Type.tuple([
                Type.variablePattern("a"),
                Type.variablePattern("b"),
              ]),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
          },
        });
      });

      it("{{{a, b} = {c, d}} = {{e, f}}} = {{{1, 2}}}", () => {
        const result = Interpreter.matchOperator(
          Type.tuple([
            Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
          ]),
          Type.tuple([
            Interpreter.matchOperator(
              Type.tuple([
                Type.tuple([
                  Type.variablePattern("e"),
                  Type.variablePattern("f"),
                ]),
              ]),
              Type.tuple([
                Interpreter.matchOperator(
                  Type.tuple([
                    Type.variablePattern("c"),
                    Type.variablePattern("d"),
                  ]),
                  Type.tuple([
                    Type.variablePattern("a"),
                    Type.variablePattern("b"),
                  ]),
                  context,
                ),
              ]),
              context,
            ),
          ]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.tuple([
            Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
          ]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            a: Type.integer(1),
            b: Type.integer(2),
            c: Type.integer(1),
            d: Type.integer(2),
            e: Type.integer(1),
            f: Type.integer(2),
          },
        });
      });
    });

    // TODO: finish overhaul, remember about Elixir consistency tests
    // describe("tuple type", () => {
    //   let tuple1;
    //   beforeEach(() => {
    //     tuple1 = Type.tuple([Type.integer(1), Type.integer(2)]);
    //   });
    //   it("{1, 2} = {1, 2}", () => {
    //     const result = Interpreter.matchOperator(tuple1, tuple1, vars);
    //     assert.deepStrictEqual(result, tuple1);
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("{1, 2} = {1, 3}", () => {
    //     const tuple2 = Type.tuple([Type.integer(1), Type.integer(3)]);
    //     assertMatchError(
    //       () => Interpreter.matchOperator(tuple2, tuple1, vars),
    //       tuple2,
    //     );
    //   });
    //   it("{1, 2} = :abc", () => {
    //     const myAtom = Type.atom("abc");
    //     assertMatchError(
    //       () => Interpreter.matchOperator(myAtom, tuple1, vars),
    //       myAtom,
    //     );
    //   });
    //   it("{} = {1, 2}", () => {
    //     assertMatchError(
    //       () => Interpreter.matchOperator(tuple1, Type.tuple([]), vars),
    //       tuple1,
    //     );
    //   });
    //   it("{1, 2} = {}", () => {
    //     const emptyTuple = Type.tuple([]);
    //     assertMatchError(
    //       () => Interpreter.matchOperator(emptyTuple, tuple1, vars),
    //       emptyTuple,
    //     );
    //   });
    //   it("{} = {}", () => {
    //     const emptyTuple = Type.tuple([]);
    //     const result = Interpreter.matchOperator(emptyTuple, emptyTuple, vars);
    //     assert.deepStrictEqual(result, emptyTuple);
    //     assert.deepStrictEqual(vars, {a: Type.integer(9)});
    //   });
    //   it("{x, 2, y} = {1, 2, 3}", () => {
    //     const left = Type.tuple([
    //       Type.variablePattern("x"),
    //       Type.integer(2),
    //       Type.variablePattern("y"),
    //     ]);
    //     const right = Type.tuple([
    //       Type.integer(1),
    //       Type.integer(2),
    //       Type.integer(3),
    //     ]);
    //     const result = Interpreter.matchOperator(right, left, vars);
    //     assert.deepStrictEqual(result, right);
    //     const expectedVars = {
    //       a: Type.integer(9),
    //       x: Type.integer(1),
    //       y: Type.integer(3),
    //     };
    //     assert.deepStrictEqual(vars, expectedVars);
    //   });
    // });

    describe("variable pattern", () => {
      // x = 2
      it("variable pattern == anything", () => {
        const result = Interpreter.matchOperator(
          Type.integer(2),
          Type.variablePattern("x"),
          context,
        );

        assert.deepStrictEqual(result, Type.integer(2));

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(2),
          },
        });
      });

      // [x, x] = [1, 1]
      it("multiple variables with the same name being matched to the same value", () => {
        const result = Interpreter.matchOperator(
          Type.list([Type.integer(1), Type.integer(1)]),
          Type.list([Type.variablePattern("x"), Type.variablePattern("x")]),
          context,
        );

        assert.deepStrictEqual(
          result,
          Type.list([Type.integer(1), Type.integer(1)]),
        );

        assert.deepStrictEqual(context.vars, {
          a: Type.integer(9),
          __matched__: {
            x: Type.integer(1),
          },
        });
      });

      // [x, x] = [1, 2]
      it("multiple variables with the same name being matched to the different values", () => {
        const left = Type.list([
          Type.variablePattern("x"),
          Type.variablePattern("x"),
        ]);

        const right = Type.list([Type.integer(1), Type.integer(2)]);

        assertBoxedError(
          () => Interpreter.matchOperator(right, left, context),
          "MatchError",
          "no match of right hand side value: [1, 2]",
        );
      });
    });

    describe("named function params", () => {
      it("(a = 1)", () => {
        const alias = Type.alias(
          "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
        );

        const fun = Type.atom("test_a");
        const args = Type.list([Type.integer(1)]);
        const result = Interpreter.callNamedFunction(alias, fun, args);

        assert.deepStrictEqual(
          result,
          Type.map([[Type.atom("a"), Type.integer(1)]]),
        );
      });

      it("(1 = a)", () => {
        const alias = Type.alias(
          "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
        );

        const fun = Type.atom("test_b");
        const args = Type.list([Type.integer(1)]);
        const result = Interpreter.callNamedFunction(alias, fun, args);

        assert.deepStrictEqual(
          result,
          Type.map([[Type.atom("a"), Type.integer(1)]]),
        );
      });

      it("(a = b = 1)", () => {
        const alias = Type.alias(
          "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
        );

        const fun = Type.atom("test_c");
        const args = Type.list([Type.integer(1)]);
        const result = Interpreter.callNamedFunction(alias, fun, args);

        assert.deepStrictEqual(
          result,
          Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(1)],
          ]),
        );
      });

      it("(a = 1 = b)", () => {
        const alias = Type.alias(
          "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
        );

        const fun = Type.atom("test_d");
        const args = Type.list([Type.integer(1)]);
        const result = Interpreter.callNamedFunction(alias, fun, args);

        assert.deepStrictEqual(
          result,
          Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(1)],
          ]),
        );
      });
    });
  });

  describe("maybeInitModuleProxy()", () => {
    beforeEach(() => delete globalThis.Elixir_MyModuleExName);

    it("proxy hasn't been initiated yet", () => {
      Interpreter.maybeInitModuleProxy(
        "MyModuleExName",
        "Elixir_MyModuleExName",
      );

      assert.deepStrictEqual(
        globalThis.Elixir_MyModuleExName.__exModule__,
        Type.alias("MyModuleExName"),
      );

      assert.deepStrictEqual(
        globalThis.Elixir_MyModuleExName.__exports__,
        new Set(),
      );

      assert.equal(
        globalThis.Elixir_MyModuleExName.__jsName__,
        "Elixir_MyModuleExName",
      );

      globalThis.Elixir_MyModuleExName["my_defined_fun/3"] = () =>
        "my_defined_fun/3 result";

      assert.equal(
        globalThis.Elixir_MyModuleExName["my_defined_fun/3"](),
        "my_defined_fun/3 result",
      );

      assertBoxedError(
        () => globalThis.Elixir_MyModuleExName["my_undefined_fun/3"](),
        "UndefinedFunctionError",
        Interpreter.buildUndefinedFunctionErrorMsg(
          Type.alias("MyModuleExName"),
          "my_undefined_fun",
          3,
        ),
      );
    });

    it("proxy has been already initiated", () => {
      Interpreter.maybeInitModuleProxy(
        "MyModuleExName",
        "Elixir_MyModuleExName",
      );

      globalThis.Elixir_MyModuleExName["my_defined_fun/3"] = () =>
        "my_defined_fun/3 result";

      globalThis.Elixir_MyModuleExName.__exports__.add("my_defined_fun/3");

      Interpreter.maybeInitModuleProxy(
        "MyModuleExName",
        "Elixir_MyModuleExName",
      );

      assert.equal(
        globalThis.Elixir_MyModuleExName["my_defined_fun/3"](),
        "my_defined_fun/3 result",
      );

      assert.deepStrictEqual(
        globalThis.Elixir_MyModuleExName.__exports__,
        new Set(["my_defined_fun/3"]),
      );
    });
  });

  it("moduleExName()", () => {
    const name = "Aaa.Bbb.Ccc";
    const alias = Type.alias(name);
    const result = Interpreter.moduleExName(alias);

    assert.equal(result, name);
  });

  describe("moduleJsName()", () => {
    describe("boxed alias argument", () => {
      it("Elixir module alias without camel case segments", () => {
        const alias = Type.atom("Elixir.Aaa.Bbb.Ccc");
        const result = Interpreter.moduleJsName(alias);

        assert.equal(result, "Elixir_Aaa_Bbb_Ccc");
      });

      it("Elixir module alias with camel case segments", () => {
        const alias = Type.atom("Elixir.AaaBbb.CccDdd");
        const result = Interpreter.moduleJsName(alias);

        assert.equal(result, "Elixir_AaaBbb_CccDdd");
      });

      it(":erlang alias", () => {
        const alias = Type.atom("erlang");
        const result = Interpreter.moduleJsName(alias);

        assert.equal(result, "Erlang");
      });

      it("single-segment Erlang module alias", () => {
        const alias = Type.atom("aaa");
        const result = Interpreter.moduleJsName(alias);

        assert.equal(result, "Erlang_Aaa");
      });

      it("multiple-segment Erlang module alias", () => {
        const alias = Type.atom("aaa_bbb");
        const result = Interpreter.moduleJsName(alias);

        assert.equal(result, "Erlang_Aaa_Bbb");
      });
    });

    describe("JS string argument", () => {
      it("Elixir module alias without camel case segments", () => {
        const result = Interpreter.moduleJsName("Elixir.Aaa.Bbb.Ccc");
        assert.equal(result, "Elixir_Aaa_Bbb_Ccc");
      });

      it("Elixir module alias with camel case segments", () => {
        const result = Interpreter.moduleJsName("Elixir.AaaBbb.CccDdd");
        assert.equal(result, "Elixir_AaaBbb_CccDdd");
      });

      it(":erlang alias", () => {
        const result = Interpreter.moduleJsName("erlang");
        assert.equal(result, "Erlang");
      });

      it("single-segment Erlang module alias", () => {
        const result = Interpreter.moduleJsName("aaa");
        assert.equal(result, "Erlang_Aaa");
      });

      it("multiple-segment Erlang module alias", () => {
        const result = Interpreter.moduleJsName("aaa_bbb");
        assert.equal(result, "Erlang_Aaa_Bbb");
      });
    });
  });

  describe("moduleProxy()", () => {
    it("boxed alias argument", () => {
      const alias = Type.alias("String.Chars");
      const result = Interpreter.moduleProxy(alias);

      assert.equal(result, Elixir_String_Chars);
    });

    it("JS string argument", () => {
      const alias = "Elixir.String.Chars";
      const result = Interpreter.moduleProxy(alias);

      assert.equal(result, Elixir_String_Chars);
    });
  });

  it("raiseArgumentError()", () => {
    assertBoxedError(
      () => Interpreter.raiseArgumentError("abc"),
      "ArgumentError",
      "abc",
    );
  });

  describe("raiseArithmeticError()", () => {
    it("without blame info", () => {
      assertBoxedError(
        () => Interpreter.raiseArithmeticError(),
        "ArithmeticError",
        "bad argument in arithmetic expression",
      );
    });

    it("with blame info", () => {
      assertBoxedError(
        () => Interpreter.raiseArithmeticError("my blame"),
        "ArithmeticError",
        "bad argument in arithmetic expression: my blame",
      );
    });
  });

  describe("raiseBadArityError()", () => {
    it("called with no args", () => {
      assertBoxedError(
        () => Interpreter.raiseBadArityError(1, []),
        "BadArityError",
        "anonymous function with arity 1 called with no arguments",
      );
    });

    it("called with a single arg", () => {
      assertBoxedError(
        () => Interpreter.raiseBadArityError(2, [Type.integer(9)]),
        "BadArityError",
        "anonymous function with arity 2 called with 1 argument (9)",
      );
    });

    it("called with multiple args", () => {
      assertBoxedError(
        () =>
          Interpreter.raiseBadArityError(1, [Type.integer(9), Type.integer(8)]),
        "BadArityError",
        "anonymous function with arity 1 called with 2 arguments (9, 8)",
      );
    });
  });

  it("raiseBadFunctionError()", () => {
    const term = Type.atom("abc");

    assertBoxedError(
      () => Interpreter.raiseBadFunctionError(term),
      "BadFunctionError",
      Interpreter.buildBadFunctionErrorMsg(term),
    );
  });

  it("raiseBadMapError()", () => {
    assertBoxedError(
      () => Interpreter.raiseBadMapError(Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });

  it("raiseCaseClauseError()", () => {
    assertBoxedError(
      () => Interpreter.raiseCaseClauseError(Type.atom("abc")),
      "CaseClauseError",
      "no case clause matching: :abc",
    );
  });

  it("raiseCompileError()", () => {
    assertBoxedError(
      () => Interpreter.raiseCompileError("abc"),
      "CompileError",
      "abc",
    );
  });

  it("raiseErlangError()", () => {
    assertBoxedError(
      () => Interpreter.raiseErlangError("abc"),
      "ErlangError",
      "abc",
    );
  });

  it("raiseError()", () => {
    assertBoxedError(
      () => Interpreter.raiseError("Aaa.Bbb", "abc"),
      "Aaa.Bbb",
      "abc",
    );
  });

  it("raiseFunctionClauseError()", () => {
    assertBoxedError(
      () => Interpreter.raiseFunctionClauseError("my_message"),
      "FunctionClauseError",
      "my_message",
    );
  });

  it("raiseKeyError()", () => {
    assertBoxedError(() => Interpreter.raiseKeyError("abc"), "KeyError", "abc");
  });

  it("raiseMatchError()", () => {
    assertBoxedError(
      () => Interpreter.raiseMatchError("my_message"),
      "MatchError",
      "my_message",
    );
  });

  it("raiseProtocolUndefinedError()", () => {
    const term = Type.tuple([Type.integer(1), Type.integer(2)]);

    assertBoxedError(
      () => Interpreter.raiseProtocolUndefinedError("String.Chars", term),
      "Protocol.UndefinedError",
      Interpreter.buildProtocolUndefinedErrorMsg("String.Chars", term),
    );
  });

  it("raiseUndefinedFunctionError()", () => {
    assertBoxedError(
      () => Interpreter.raiseUndefinedFunctionError("my_message"),
      "UndefinedFunctionError",
      "my_message",
    );
  });

  describe("try()", () => {
    let context;

    beforeEach(() => {
      context = contextFixture({
        vars: {
          a: Type.integer(1),
          b: Type.integer(2),
        },
      });
    });

    it("body without any errors, throws or exists / vars are not mutated in body", () => {
      // try do
      //   a = 3
      //   :ok
      // end
      const body = (context) => {
        Interpreter.matchOperator(
          Type.integer(3),
          Type.variablePattern("a"),
          context,
        );
        return Type.atom("ok");
      };

      const result = Interpreter.try(body, [], [], [], null, context);

      assert.deepStrictEqual(result, Type.atom("ok"));
      assert.deepStrictEqual(context.vars.a, Type.integer(1));
    });
  });

  it("updateVarsToMatchedValues()", () => {
    const context = contextFixture({
      vars: {
        a: 1,
        b: 2,
        c: 3,
        __matched__: {
          d: 4,
          a: 11,
          e: 5,
          c: 33,
        },
      },
    });

    const result = Interpreter.updateVarsToMatchedValues(context);

    const expected = contextFixture({
      vars: {
        a: 11,
        b: 2,
        c: 33,
        d: 4,
        e: 5,
      },
    });

    assert.equal(result, context);
    assert.deepStrictEqual(result, expected);
  });

  // TODO: finish implementing
  it("with()", () => {
    assert.throw(
      () => Interpreter.with(),
      Error,
      '"with" expression is not yet implemented in Hologram',
    );
  });
});
