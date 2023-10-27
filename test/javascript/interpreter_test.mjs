"use strict";

import {
  assert,
  assertBoxedError,
  assertMatchError,
  linkModules,
  sinon,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Erlang from "../../assets/js/erlang/erlang.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

describe("callAnonymousFunction()", () => {
  let vars, anonFun;

  beforeEach(() => {
    vars = {a: Type.integer(5), b: Type.integer(6), x: Type.integer(9)};

    // fn
    //   1 -> :expr_1
    //   2 -> :expr_2
    // end
    anonFun = Type.anonymousFunction(
      1,
      [
        {
          params: (_vars) => [Type.integer(1)],
          guards: [],
          body: (_vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_vars) => [Type.integer(2)],
          guards: [],
          body: (_vars) => {
            return Type.atom("expr_2");
          },
        },
      ],
      vars,
    );
  });

  it("runs the first matching clause", () => {
    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result, Type.atom("expr_1"));
  });

  it("ignores not matching clauses", () => {
    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(2),
    ]);

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("runs guards for each tried clause", () => {
    // fn
    //   x when x == 1 -> :expr_1
    //   y when y == 2 -> :expr_2
    //   z when z == 3 -> :expr_3
    // end
    const anonFun = Type.anonymousFunction(
      1,
      [
        {
          params: (_vars) => [Type.variablePattern("x")],
          guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
          body: (_vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_vars) => [Type.variablePattern("y")],
          guards: [(vars) => Erlang["==/2"](vars.y, Type.integer(2))],
          body: (_vars) => {
            return Type.atom("expr_2");
          },
        },
        {
          params: (_vars) => [Type.variablePattern("z")],
          guards: [(vars) => Erlang["==/2"](vars.z, Type.integer(3))],
          body: (_vars) => {
            return Type.atom("expr_3");
          },
        },
      ],
      vars,
    );

    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(3),
    ]);

    assert.deepStrictEqual(result, Type.atom("expr_3"));
  });

  it("runs mutliple guards", () => {
    // fn x when x == 1 when x == 2 -> x end
    //
    // fn x when :erlang.==(x, 1) when :erlang.==(x, 2) -> x end
    const anonFun = Type.anonymousFunction(
      1,
      [
        {
          params: (_vars) => [Type.variablePattern("x")],
          guards: [
            (vars) => Erlang["==/2"](vars.x, Type.integer(1)),
            (vars) => Erlang["==/2"](vars.x, Type.integer(2)),
          ],
          body: (vars) => {
            return vars.x;
          },
        },
      ],
      vars,
    );

    const result1 = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result1, Type.integer(1));

    const result2 = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(2),
    ]);

    assert.deepStrictEqual(result2, Type.integer(2));

    assertBoxedError(
      () => Interpreter.callAnonymousFunction(anonFun, [Type.integer(3)]),
      "FunctionClauseError",
      "no function clause matching in anonymous fn/1",
    );
  });

  it("clones vars for each clause and has access to vars from closure", () => {
    // x = 9
    //
    // fn
    //   x, 1 when x == 1 -> :expr_1
    //   y, 2 -> x
    // end
    const anonFun = Type.anonymousFunction(
      2,
      [
        {
          params: (_vars) => [Type.variablePattern("x"), Type.integer(1)],
          guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
          body: (_vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: (_vars) => [Type.variablePattern("y"), Type.integer(2)],
          guards: [],
          body: (vars) => {
            return vars.x;
          },
        },
      ],
      vars,
    );

    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(2),
      Type.integer(2),
    ]);

    assert.deepStrictEqual(result, Type.integer(9));
  });

  it("raises FunctionClauseError error if none of the clauses is matched", () => {
    assertBoxedError(
      () => Interpreter.callAnonymousFunction(anonFun, [Type.integer(3)]),
      "FunctionClauseError",
      "no function clause matching in anonymous fn/1",
    );
  });

  it("has match operator in the clause pattern", () => {
    // fn x = 1 = y -> x + y end
    const anonFun = Type.anonymousFunction(
      1,
      [
        {
          params: (vars) => [
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("y"),
                Type.integer(1n),
                vars,
                false,
              ),
              Type.variablePattern("x"),
              vars,
            ),
          ],
          guards: [],
          body: (vars) => {
            return Erlang["+/2"](vars.x, vars.y);
          },
        },
      ],
      vars,
    );

    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(1),
    ]);

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("errors raised inside function body are not caught", () => {
    const anonFun = Type.anonymousFunction(
      0,
      [
        {
          params: (_vars) => [],
          guards: [],
          body: (_vars) => Interpreter.raiseArgumentError("my message"),
        },
      ],
      vars,
    );

    assertBoxedError(
      () => Interpreter.callAnonymousFunction(anonFun, []),
      "ArgumentError",
      "my message",
    );
  });
});

it("callNamedFunction()", () => {
  // setup
  globalThis.Elixir_MyModule = {
    "my_fun/2": (arg1, arg2) => {
      return Erlang["+/2"](arg1, arg2);
    },
  };

  const alias = Type.alias("MyModule");
  const args = [Type.integer(1), Type.integer(2)];
  const result = Interpreter.callNamedFunction(alias, "my_fun/2", args);

  assert.deepStrictEqual(result, Type.integer(3));

  // cleanup
  delete globalThis.Elixir_MyModule;
});

describe("case()", () => {
  let vars;

  beforeEach(() => {
    vars = {a: Type.integer(5), b: Type.integer(6), x: Type.integer(9)};
  });

  it("returns the result of the first matching clause's block (and ignores non-matching clauses)", () => {
    // case 2 do
    //   1 -> :expr_1
    //   2 -> :expr_2
    //   3 -> :expr_3
    // end

    const clause1 = {
      match: Type.integer(1),
      guards: [],
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      match: Type.integer(2),
      guards: [],
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      match: Type.integer(3),
      guards: [],
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const result = Interpreter.case(
      Type.integer(2),
      [clause1, clause2, clause3],
      vars,
    );

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("runs guards for each tried clause", () => {
    // case 2 do
    //   x when x == 1 -> :expr_1
    //   y when y == 2 -> :expr_2
    //   z when z == 3 -> :expr_3
    // end
    //
    // case 2 do
    //   x when :erlang.==(x, 1) -> :expr_1
    //   y when :erlang.==(y, 2) -> :expr_2
    //   z when :erlang.==(z, 3) -> :expr_3
    // end

    const clause1 = {
      match: Type.variablePattern("x"),
      guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      match: Type.variablePattern("y"),
      guards: [(vars) => Erlang["==/2"](vars.y, Type.integer(2))],
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      match: Type.variablePattern("z"),
      guards: [(vars) => Erlang["==/2"](vars.z, Type.integer(3))],
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const result = Interpreter.case(
      Type.integer(2),
      [clause1, clause2, clause3],
      vars,
    );

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("clause with multiple guards", () => {
    // case my_var do
    //   x when x == 1 when x == 11 -> :expr_1
    //   y when y == 2 when y == 22 -> :expr_2
    //   z when z == 3 when z == 33 -> :expr_3
    // end
    //
    // case my_var do
    //   x when :erlang.==(x, 1) when :erlang.==(x, 11) -> :expr_1
    //   y when :erlang.==(y, 2) when :erlang.==(y, 22) -> :expr_2
    //   z when :erlang.==(z, 3) when :erlang.==(z, 33) -> :expr_3
    // end

    const clause1 = {
      match: Type.variablePattern("x"),
      guards: [
        (vars) => Erlang["==/2"](vars.x, Type.integer(1)),
        (vars) => Erlang["==/2"](vars.x, Type.integer(11)),
      ],
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      match: Type.variablePattern("y"),
      guards: [
        (vars) => Erlang["==/2"](vars.y, Type.integer(2)),
        (vars) => Erlang["==/2"](vars.y, Type.integer(22)),
      ],
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      match: Type.variablePattern("z"),
      guards: [
        (vars) => Erlang["==/2"](vars.z, Type.integer(3)),
        (vars) => Erlang["==/2"](vars.z, Type.integer(33)),
      ],
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const vars = {my_var: Type.integer(22)};

    const result = Interpreter.case(
      vars.my_var,
      [clause1, clause2, clause3],
      vars,
    );

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("clones vars for each clause and has access to vars from closure", () => {
    // x = 9
    //
    // case 2 do
    //   x when x == 1 -> :expr_1
    //   y -> x
    // end

    const clause1 = {
      match: Type.variablePattern("x"),
      guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      match: Type.variablePattern("y"),
      guards: [],
      body: (vars) => {
        return vars.x;
      },
    };

    const result = Interpreter.case(Type.integer(2), [clause1, clause2], vars);

    assert.deepStrictEqual(result, Type.integer(9));
  });

  it("raises CaseClauseError error if none of the clauses is matched", () => {
    // case 3 do
    //   1 -> :expr_1
    //   2 -> :expr_2
    // end

    const clause1 = {
      match: Type.integer(1),
      guards: [],
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      match: Type.integer(2),
      guards: [],
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    assertBoxedError(
      () => Interpreter.case(Type.integer(3), [clause1, clause2], vars),
      "CaseClauseError",
      "no case clause matching: 3",
    );
  });

  it("errors raised inside case clause are not caught", () => {
    const clause = {
      match: Type.integer(1),
      guards: [],
      body: (_vars) => Interpreter.raiseArgumentError("my message"),
    };

    assertBoxedError(
      () => Interpreter.case(Type.integer(1), [clause], vars),
      "ArgumentError",
      "my message",
    );
  });
});

describe("cloneVars()", () => {
  it("clones vars recursively (deep clone) and removes __snapshot__ property", () => {
    const nested = {c: 3, d: 4};
    const vars = {a: 1, b: nested, __snapshot__: "dummy"};
    const expected = {a: 1, b: nested};
    const result = Interpreter.cloneVars(vars);

    assert.deepStrictEqual(result, expected);
    assert.notEqual(result.b, nested);
  });
});

describe("comprehension()", () => {
  let vars, prevIntoFun, prevToListFun;

  beforeEach(() => {
    vars = {a: Type.integer(1), b: Type.integer(2)};

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
        body: (_vars) => Type.list([Type.integer(1), Type.integer(2)]),
      };

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [],
        body: (_vars) => Type.list([Type.integer(3), Type.integer(4)]),
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable1 = (_vars) =>
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

      const enumerable2 = (_vars) =>
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
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
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
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
      );

      sinon.assert.calledWith(stub, enumerable1(vars));
      sinon.assert.calledWith(stub, enumerable2(vars));
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

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

      const guard1a = (vars) => Erlang["/=/2"](vars.x, Type.integer(2));

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [guard1a],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
        Type.list([Type.integer(4), Type.integer(5), Type.integer(6)]);

      const guard2a = (vars) => Erlang["/=/2"](vars.y, Type.integer(4));

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [guard2a],
        body: enumerable2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable1 = (_vars) =>
        Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

      const guard1a = (vars) => Erlang["==/2"](vars.x, Type.integer(2));
      const guard1b = (vars) => Erlang["==/2"](vars.x, Type.integer(4));

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [guard1a, guard1b],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
        Type.list([
          Type.integer(5),
          Type.integer(6),
          Type.integer(7),
          Type.integer(8),
        ]);

      const guard2a = (vars) => Erlang["==/2"](vars.y, Type.integer(5));
      const guard2b = (vars) => Erlang["==/2"](vars.y, Type.integer(7));

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [guard2a, guard2b],
        body: enumerable2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

      const guard = (vars) => Erlang["/=/2"](vars.x, vars.b);

      const generator = {
        match: Type.variablePattern("x"),
        guards: [guard],
        body: enumerable,
      };

      const result = Interpreter.comprehension(
        [generator],
        [],
        Type.list([]),
        false,
        (vars) => vars.x,
        vars,
      );

      const expected = Type.list([Type.integer(1), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });

    it("can access variables pattern matched in preceding guards", () => {
      // for x <- [1, 2], y when x != 1 <- [3, 4], do: {x, y}

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
        Type.list([Type.integer(3), Type.integer(4)]);

      const guard2 = (vars) => Erlang["/=/2"](vars.x, Type.integer(1));

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [guard2],
        body: enumerable2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
      );

      const expected = Type.list([
        Type.tuple([Type.integer(2), Type.integer(3)]),
        Type.tuple([Type.integer(2), Type.integer(4)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("errors raised inside generators are not caught", () => {
      const enumerable = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

      const guard = (_vars) => Interpreter.raiseArgumentError("my message");

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
            Type.list([]),
            false,
            (vars) => vars.x,
            vars,
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

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
        Type.list([Type.integer(4), Type.integer(5), Type.integer(6)]);

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [],
        body: enumerable2,
      };

      const filters = [
        (vars) => Erlang["</2"](Erlang["+/2"](vars.x, vars.y), Type.integer(8)),
        (vars) => Erlang[">/2"](Erlang["-/2"](vars.y, vars.x), Type.integer(2)),
      ];

      const result = Interpreter.comprehension(
        [generator1, generator2],
        filters,
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);

      const generator = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable,
      };

      const filter = (vars) => Erlang["/=/2"](vars.x, vars.b);

      const result = Interpreter.comprehension(
        [generator],
        [filter],
        Type.list([]),
        false,
        (vars) => vars.x,
        vars,
      );

      const expected = Type.list([Type.integer(1), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("unique", () => {
    it("non-unique items are removed if 'uniq' option is set to true", () => {
      // for x <- [1, 2, 1], y <- [3, 4, 3], do: {x, y}

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2), Type.integer(1)]);

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
        Type.list([Type.integer(3), Type.integer(4), Type.integer(3)]);

      const generator2 = {
        match: Type.variablePattern("y"),
        guards: [],
        body: enumerable2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        true,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
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

      const enumerable = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2)]);

      const generator = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable,
      };

      const result = Interpreter.comprehension(
        [generator],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.b]),
        vars,
      );

      const expected = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.tuple([Type.integer(2), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("uses Enum.into/2 to insert the comprehension result into a collectable", () => {
      // for x <- [1, 2], y <- [3, 4], do: {x, y}

      const enumerable1 = (_vars) =>
        Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        match: Type.variablePattern("x"),
        guards: [],
        body: enumerable1,
      };

      const enumerable2 = (_vars) =>
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
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars,
      );

      const expectedArg = Type.list([
        Type.tuple([Type.integer(1), Type.integer(3)]),
        Type.tuple([Type.integer(1), Type.integer(4)]),
        Type.tuple([Type.integer(2), Type.integer(3)]),
        Type.tuple([Type.integer(2), Type.integer(4)]),
      ]);

      assert.isTrue(stub.calledOnceWith(expectedArg));
    });
  });
});

describe("cond()", () => {
  let vars;

  beforeEach(() => {
    vars = {a: Type.integer(5), b: Type.integer(6), x: Type.integer(9)};
  });

  it("returns the result of the block of the first clause whose condition evaluates to a truthy value (and ignores other clauses)", () => {
    // cond do
    //   nil -> :expr_1
    //   2 -> :expr_2
    //   3 -> :expr_3
    // end

    const clause1 = {
      condition: (_vars) => Type.nil(),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      condition: (_vars) => Type.integer(2),
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      condition: (_vars) => Type.integer(3),
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const result = Interpreter.cond([clause1, clause2, clause3], vars);

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("clones vars for each clause and has access to vars from closure", () => {
    // x = 9
    //
    // cond do
    //   x = false -> :expr_1
    //   true -> x
    // end

    const clause1 = {
      condition: (vars) =>
        Interpreter.matchOperator(
          Type.boolean(false),
          Type.variablePattern("x"),
          vars,
        ),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      condition: (_vars) => Type.boolean(true),
      body: (vars) => {
        return vars.x;
      },
    };

    const result = Interpreter.cond([clause1, clause2], vars);

    assert.deepStrictEqual(result, Type.integer(9));
  });

  it("raises CaseClauseError error if none of the clauses conditions evaluate to a truthy value", () => {
    // cond do
    //   nil -> :expr_1
    //   false -> :expr_2
    // end

    const clause1 = {
      condition: (_vars) => Type.nil(),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      condition: (_vars) => Type.boolean(false),
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    assertBoxedError(
      () => Interpreter.cond([clause1, clause2], vars),
      "CondClauseError",
      "no cond clause evaluated to a truthy value",
    );
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
    const tail = Type.list([]);
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
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_a", 1, [
      {
        params: (_vars) => [Type.integer(1)],
        guards: [],
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: (_vars) => [Type.integer(2)],
        guards: [],
        body: (_vars) => {
          return Type.atom("expr_2");
        },
      },
    ]);
  });

  afterEach(() => {
    delete globalThis.Elixir_Aaa_Bbb;
  });

  it("initiates the module global var if it is not initiated yet", () => {
    Interpreter.defineElixirFunction("Elixir_Ddd", "my_fun_d", 4, []);

    assert.isDefined(globalThis.Elixir_Ddd);
    assert.isDefined(globalThis.Elixir_Ddd["my_fun_d/4"]);

    // cleanup
    delete globalThis.Elixir_Ddd;
  });

  it("appends to the module global var if it is already initiated", () => {
    globalThis.Elixir_Eee = {"dummy/1": "dummy_body"};
    Interpreter.defineElixirFunction("Elixir_Eee", "my_fun_e", 5, []);

    assert.isDefined(globalThis.Elixir_Eee);
    assert.isDefined(globalThis.Elixir_Eee["my_fun_e/5"]);
    assert.equal(globalThis.Elixir_Eee["dummy/1"], "dummy_body");

    // cleanup
    delete globalThis.Elixir_Eee;
  });

  it("defines function with multiple params", () => {
    // def my_fun_e(1, 2, 3), do: :ok
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_e", 3, [
      {
        params: (_vars) => [Type.integer(1), Type.integer(2), Type.integer(3)],
        guards: [],
        body: (_vars) => {
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

  it("defines function which runs the first matching clause", () => {
    const result = globalThis.Elixir_Aaa_Bbb["my_fun_a/1"](Type.integer(1));
    assert.deepStrictEqual(result, Type.atom("expr_1"));
  });

  it("defines function which ignores not matching clauses", () => {
    const result = globalThis.Elixir_Aaa_Bbb["my_fun_a/1"](Type.integer(2));
    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("defines function which runs guards for each tried clause", () => {
    // def my_fun_b(x) when x == 1, do: :expr_1
    // def my_fun_b(y) when y == 2, do: :expr_2
    // def my_fun_b(z) when z == 3, do: :expr_3
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_b", 1, [
      {
        params: (_vars) => [Type.variablePattern("x")],
        guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: (_vars) => [Type.variablePattern("y")],
        guards: [(vars) => Erlang["==/2"](vars.y, Type.integer(2))],
        body: (_vars) => {
          return Type.atom("expr_2");
        },
      },
      {
        params: (_vars) => [Type.variablePattern("z")],
        guards: [(vars) => Erlang["==/2"](vars.z, Type.integer(3))],
        body: (_vars) => {
          return Type.atom("expr_3");
        },
      },
    ]);

    const result = globalThis.Elixir_Aaa_Bbb["my_fun_b/1"](Type.integer(3));

    assert.deepStrictEqual(result, Type.atom("expr_3"));
  });

  it("defines function with multiple guards", () => {
    // def my_fun_b(x) when x == 1 when x == 2, do: x
    //
    // def my_fun_b(x) when :erlang.==(x, 1) when :erlang.==(x, 2), do: x
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_b", 1, [
      {
        params: (_vars) => [Type.variablePattern("x")],
        guards: [
          (vars) => Erlang["==/2"](vars.x, Type.integer(1)),
          (vars) => Erlang["==/2"](vars.x, Type.integer(2)),
        ],
        body: (vars) => {
          return vars.x;
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
      "no function clause matching in Aaa.Bbb.my_fun_b/1",
    );
  });

  it("defines function which clones vars for each clause", () => {
    // def my_fun_c(x) when x == 1, do: :expr_1
    // def my_fun_c(x) when x == 2, do: :expr_2
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_c", 1, [
      {
        params: (_vars) => [Type.variablePattern("x")],
        guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(1))],
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: (_vars) => [Type.variablePattern("x")],
        guards: [(vars) => Erlang["==/2"](vars.x, Type.integer(2))],
        body: (_vars) => {
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
      "no function clause matching in Aaa.Bbb.my_fun_a/1",
    );
  });

  it("defines function which has match operator in params", () => {
    // def my_fun_d(x = 1 = y), do: x + y
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_d", 1, [
      {
        params: (vars) => [
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("y"),
              Type.integer(1),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
          ),
        ],
        guards: [],
        body: (vars) => {
          return Erlang["+/2"](vars.x, vars.y);
        },
      },
    ]);

    const result = globalThis.Elixir_Aaa_Bbb["my_fun_d/1"](Type.integer(1));

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("errors raised inside function body are not caught", () => {
    Interpreter.defineElixirFunction("Elixir_Aaa_Bbb", "my_fun_f", 0, [
      {
        params: () => [],
        guards: [],
        body: (_vars) => Interpreter.raiseArgumentError("my message"),
      },
    ]);

    assertBoxedError(
      () => globalThis.Elixir_Aaa_Bbb["my_fun_f/0"](),
      "ArgumentError",
      "my message",
    );
  });
});

describe("defineErlangFunction()", () => {
  beforeEach(() => {
    Interpreter.defineErlangFunction("Erlang_Aaa_Bbb", "my_fun_a", 2, () =>
      Type.atom("expr_a"),
    );
  });

  afterEach(() => {
    delete globalThis.Erlang_Aaa_Bbb;
  });

  it("initiates the module global var if it is not initiated yet", () => {
    Interpreter.defineErlangFunction("Erlang_Ddd", "my_fun_d", 3, []);

    assert.isDefined(globalThis.Erlang_Ddd);
    assert.isDefined(globalThis.Erlang_Ddd["my_fun_d/3"]);

    // cleanup
    delete globalThis.Erlang_Ddd;
  });

  it("appends to the module global var if it is already initiated", () => {
    globalThis.Erlang_Eee = {dummy: "dummy"};
    Interpreter.defineErlangFunction("Erlang_Eee", "my_fun_e", 1, []);

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

describe("defineNotImplementedErlangFunction()", () => {
  beforeEach(() => {
    Interpreter.defineNotImplementedErlangFunction(
      "aaa_bbb",
      "Erlang_Aaa_Bbb",
      "my_fun_a",
      2,
    );
  });

  afterEach(() => {
    delete globalThis.Erlang_Aaa_Bbb;
  });

  it("initiates the module global var if it is not initiated yet", () => {
    Interpreter.defineNotImplementedErlangFunction(
      "ddd",
      "Erlang_Ddd",
      "my_fun_d",
      3,
      [],
    );

    assert.isDefined(globalThis.Erlang_Ddd);
    assert.isDefined(globalThis.Erlang_Ddd["my_fun_d/3"]);

    // cleanup
    delete globalThis.Erlang_Ddd;
  });

  it("appends to the module global var if it is already initiated", () => {
    globalThis.Erlang_Eee = {dummy: "dummy"};
    Interpreter.defineNotImplementedErlangFunction(
      "eee",
      "Erlang_Eee",
      "my_fun_e",
      1,
      [],
    );

    assert.isDefined(globalThis.Erlang_Eee);
    assert.isDefined(globalThis.Erlang_Eee["my_fun_e/1"]);
    assert.equal(globalThis.Erlang_Eee.dummy, "dummy");

    // cleanup
    delete globalThis.Erlang_Eee;
  });

  it("defines a function which raises an exception with instructions", () => {
    const expectedMessage = `Function :aaa_bbb.my_fun_a/2 is not yet ported. See what to do here: https://www.hologram.page/TODO`;

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

describe("deserialize()", () => {
  it("deserializes number from JSON", () => {
    const result = Interpreter.deserialize("123");
    assert.equal(result, 123);
  });

  it("deserializes string from JSON", () => {
    const result = Interpreter.deserialize('"abc"');
    assert.equal(result, "abc");
  });

  it("deserializes non-negative bigint from JSON", () => {
    const result = Interpreter.deserialize('"__bigint__:123"');
    assert.equal(result, 123n);
  });

  it("deserializes negative bigint from JSON", () => {
    const result = Interpreter.deserialize('"__bigint__:-123"');
    assert.equal(result, -123n);
  });

  it("deserializes non-nested object from JSON", () => {
    const result = Interpreter.deserialize('{"a":1,"b":2}');
    assert.deepStrictEqual(result, {a: 1, b: 2});
  });

  it("deserializes nested object from JSON", () => {
    const result = Interpreter.deserialize('{"a":1,"b":2,"c":{"d":3,"e":4}}');
    const expected = {a: 1, b: 2, c: {d: 3, e: 4}};

    assert.deepStrictEqual(result, expected);
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

it("fetchErrorMessage()", () => {
  const errorStruct = Type.errorStruct("MyError", "my message");
  const jsError = new HologramBoxedError(errorStruct);
  const result = Interpreter.fetchErrorMessage(jsError);

  assert.equal(result, "my message");
});

it("fetchErrorType()", () => {
  const errorStruct = Type.errorStruct("MyError", "my message");
  const jsError = new HologramBoxedError(errorStruct);
  const result = Interpreter.fetchErrorType(jsError);

  assert.equal(result, "MyError");
});

describe("inspect()", () => {
  it("proxies to Kernel.inspect/2", () => {
    const result = Interpreter.inspect(Type.integer(123));
    assert.equal(result, "123");
  });
});

describe("inspectModuleName()", () => {
  it("inspects Elixir module name", () => {
    const result = Interpreter.inspectModuleName("Elixir_Aaa_Bbb");
    assert.deepStrictEqual(result, "Aaa.Bbb");
  });

  it("inspects 'Erlang' module name", () => {
    const result = Interpreter.inspectModuleName("Erlang");
    assert.deepStrictEqual(result, ":erlang");
  });

  it("inspects Erlang standard lib module name", () => {
    const result = Interpreter.inspectModuleName("Erlang_Uri_String");
    assert.deepStrictEqual(result, ":uri_string");
  });
});

describe("isMatched()", () => {
  it("is matched", () => {
    assert.isTrue(Interpreter.isMatched(Type.integer(1), Type.integer(1), {}));
  });

  it("is not matched", () => {
    assert.isFalse(Interpreter.isMatched(Type.integer(1), Type.integer(2), {}));
  });

  it("mutates vars given in the argument", () => {
    const vars = {};
    const result = Interpreter.isMatched(
      Type.variablePattern("x"),
      Type.integer(9),
      vars,
    );

    assert.isTrue(result);
    assert.deepStrictEqual(vars, {x: Type.integer(9)});
  });
});

describe("isStrictlyEqual()", () => {
  it("returns true if the args are of the same boxed primitive type and have equal values", () => {
    const result = Interpreter.isStrictlyEqual(
      Type.integer(1),
      Type.integer(1),
    );

    assert.isTrue(result);
  });

  it("returns false if the args are not of the same boxed primitive type but have equal values", () => {
    const result = Interpreter.isStrictlyEqual(
      Type.integer(1),
      Type.float(1.0),
    );

    assert.isFalse(result);
  });

  it("returns true if the left boxed arg of a composite type is deeply equal to the right boxed arg of a composite type", () => {
    const left = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const right = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const result = Interpreter.isStrictlyEqual(left, right);

    assert.isTrue(result);
  });

  it("returns false if the left boxed arg of a composite type is not deeply equal to the right boxed arg of a composite type", () => {
    const left = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(3)]])],
    ]);

    const right = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.map([[Type.atom("c"), Type.integer(4)]])],
    ]);

    const result = Interpreter.isStrictlyEqual(left, right);

    assert.isFalse(result);
  });
});

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/match_operator_test.exs
// Always update both together.
//
// left and right args are not stored in temporary variables but used directly in matchOperator() call,
// to make the test as close as possible to real behaviour in which the matchOperator() call is encoded as a whole.
describe("matchOperator()", () => {
  let vars;

  beforeEach(() => {
    vars = {a: Type.integer(9)};
  });

  describe("atom type", () => {
    it("left atom == right atom", () => {
      // :abc = :abc
      const result = Interpreter.matchOperator(
        Type.atom("abc"),
        Type.atom("abc"),
        vars,
      );

      assert.deepStrictEqual(result, Type.atom("abc"));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left atom != right atom", () => {
      const myAtom = Type.atom("xyz");

      // :abc = :xyz
      assertMatchError(
        () => Interpreter.matchOperator(myAtom, Type.atom("abc"), vars),
        myAtom,
      );
    });

    it("left atom != right non-atom", () => {
      const myInteger = Type.integer(2);

      // :abc = 2
      assertMatchError(
        () => Interpreter.matchOperator(myInteger, Type.atom("abc"), vars),
        myInteger,
      );
    });
  });

  describe("bitstring type", () => {
    it("left bitstring == right bitstring", () => {
      const result = Interpreter.matchOperator(
        Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]),
        Type.bitstringPattern([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        ]),
        vars,
      );

      const expected = Type.bitstring([
        Type.bitstringSegment(Type.integer(1), {type: "integer"}),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("left bitstring != right bitstring", () => {
      const myBitstring = Type.bitstring([
        Type.bitstringSegment(Type.integer(2), {type: "integer"}),
      ]);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            myBitstring,
            Type.bitstringPattern([
              Type.bitstringSegment(Type.integer(1), {type: "integer"}),
            ]),
            vars,
          ),
        myBitstring,
      );
    });

    it("left bitstring != right non-bitstring", () => {
      const myAtom = Type.atom("abc");

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            myAtom,
            Type.bitstring([
              Type.bitstringSegment(Type.integer(1), {type: "integer"}),
            ]),
            vars,
          ),
        myAtom,
      );
    });

    it("literal bitstring segments", () => {
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
        vars,
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

      assert.deepStrictEqual(result, expected);
    });

    it("literal float segments", () => {
      const result = Interpreter.matchOperator(
        Type.bitstring([
          Type.bitstringSegment(Type.float(1.0), {type: "float"}),
          Type.bitstringSegment(Type.float(2.0), {type: "float"}),
        ]),
        Type.bitstringPattern([
          Type.bitstringSegment(Type.float(1.0), {type: "float"}),
          Type.bitstringSegment(Type.float(2.0), {type: "float"}),
        ]),
        vars,
      );

      const expected = Type.bitstring([
        Type.bitstringSegment(Type.float(1.0), {type: "float"}),
        Type.bitstringSegment(Type.float(2.0), {type: "float"}),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("literal integer segments", () => {
      const result = Interpreter.matchOperator(
        Type.bitstring([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]),
        Type.bitstringPattern([
          Type.bitstringSegment(Type.integer(1), {type: "integer"}),
          Type.bitstringSegment(Type.integer(2), {type: "integer"}),
        ]),
        vars,
      );

      const expected = Type.bitstring([
        Type.bitstringSegment(Type.integer(1), {type: "integer"}),
        Type.bitstringSegment(Type.integer(2), {type: "integer"}),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("literal string segments", () => {
      const result = Interpreter.matchOperator(
        Type.bitstring([
          Type.bitstringSegment(Type.string("aaa"), {type: "utf8"}),
          Type.bitstringSegment(Type.string("bbb"), {type: "utf8"}),
        ]),
        Type.bitstringPattern([
          Type.bitstringSegment(Type.string("aaa"), {type: "utf8"}),
          Type.bitstringSegment(Type.string("bbb"), {type: "utf8"}),
        ]),
        vars,
      );

      const expected = Type.bitstring([
        Type.bitstringSegment(Type.string("aaa"), {type: "utf8"}),
        Type.bitstringSegment(Type.string("bbb"), {type: "utf8"}),
      ]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("cons pattern", () => {
    describe("[h | t]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.variablePattern("t"),
        );
      });

      it("[h | t] = 1", () => {
        const right = Type.integer(1);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | t] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | t] = [1]", () => {
        const right = Type.list([Type.integer(1)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
          t: Type.list([]),
        });
      });

      it("[h | t] = [1, 2]", () => {
        const right = Type.list([Type.integer(1), Type.integer(2)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
          t: Type.list([Type.integer(2)]),
        });
      });

      it("[h | t] = [1 | 2]", () => {
        const right = Type.improperList([Type.integer(1), Type.integer(2)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
          t: Type.integer(2),
        });
      });

      it("[h | t] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
          t: Type.list([Type.integer(2), Type.integer(3)]),
        });
      });

      it("[h | t] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
          t: Type.improperList([Type.integer(2), Type.integer(3)]),
        });
      });
    });

    describe("[1 | t]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(Type.integer(1), Type.variablePattern("t"));
      });

      it("[1 | t] = 1", () => {
        const right = Type.integer(1);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = [1]", () => {
        const right = Type.list([Type.integer(1)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          t: Type.list([]),
        });
      });

      it("[1 | t] = [5]", () => {
        const right = Type.list([Type.integer(5)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = [1, 2]", () => {
        const right = Type.list([Type.integer(1), Type.integer(2)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          t: Type.list([Type.integer(2)]),
        });
      });

      it("[1 | t] = [5, 2]", () => {
        const right = Type.list([Type.integer(5), Type.integer(2)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = [1 | 2]", () => {
        const right = Type.improperList([Type.integer(1), Type.integer(2)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          t: Type.integer(2),
        });
      });

      it("[1 | t] = [5 | 2]", () => {
        const right = Type.improperList([Type.integer(5), Type.integer(2)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          t: Type.list([Type.integer(2), Type.integer(3)]),
        });
      });

      it("[1 | t] = [5, 2, 3]", () => {
        const right = Type.list([
          Type.integer(5),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | t] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          t: Type.improperList([Type.integer(2), Type.integer(3)]),
        });
      });

      it("[1 | t] = [5, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(5),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | 3]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(Type.variablePattern("h"), Type.integer(3));
      });

      it("[h | 3] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | 3] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | 3] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | 3] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | 3] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(2),
        });
      });

      it("[h | 3] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | 3] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | []]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(Type.variablePattern("h"), Type.list([]));
      });

      it("[h | []] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | []] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | []] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(3),
        });
      });

      it("[h | []] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | []] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | []] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | []] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | [3]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.list([Type.integer(3)]),
        );
      });

      it("[h | [3]] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [3]] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [3]] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [3]] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(2),
        });
      });

      it("[h | [3]] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [3]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [3]] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | [2, 3]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.list([Type.integer(2), Type.integer(3)]),
        );
      });

      it("[h | [2, 3]] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2, 3]] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2, 3]] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2, 3]] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2, 3]] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2, 3]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
        });
      });

      it("[h | [2, 3]] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | [2 | 3]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.consPattern(Type.integer(2), Type.integer(3)),
        );
      });

      it("[h | [2 | 3]] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [2 | 3]] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);

        assert.deepStrictEqual(vars, {
          a: Type.integer(9),
          h: Type.integer(1),
        });
      });
    });

    describe("[h | [1, 2, 3]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        );
      });

      it("[h | [1, 2, 3]] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2, 3]] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[h | [1, 2 | 3]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.variablePattern("h"),
          Type.consPattern(
            Type.integer(1),
            Type.consPattern(Type.integer(2), Type.integer(3)),
          ),
        );
      });

      it("[h | [1, 2 | 3]] = 3", () => {
        const right = Type.integer(3);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = []", () => {
        const right = Type.list([]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = [3]", () => {
        const right = Type.list([Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = [2, 3]", () => {
        const right = Type.list([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = [2 | 3]", () => {
        const right = Type.improperList([Type.integer(2), Type.integer(3)]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[h | [1, 2 | 3]] = [1, 2 | 3]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[1 | [2 | [3 | []]]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.integer(1),
          Type.consPattern(
            Type.integer(2),
            Type.consPattern(Type.integer(3), Type.list([])),
          ),
        );
      });

      it("[1 | [2 | [3 | []]]] = [1, 2, 3, 4]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | [2 | [3 | []]]] = [1, 2, 3 | 4]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | [2 | [3 | []]]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);
        assert.deepStrictEqual(vars, {a: Type.integer(9)});
      });
    });

    describe("[1 | [2 | [3 | 4]]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.integer(1),
          Type.consPattern(
            Type.integer(2),
            Type.consPattern(Type.integer(3), Type.integer(4)),
          ),
        );
      });

      it("[1 | [2 | [3 | 4]]] = [1, 2, 3, 4]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | [2 | [3 | 4]]] = [1, 2, 3 | 4]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);
        assert.deepStrictEqual(vars, {a: Type.integer(9)});
      });

      it("[1 | [2 | [3 | 4]]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });

    describe("[1 | [2 | [3 | [4]]]]", () => {
      let left;

      beforeEach(() => {
        left = Type.consPattern(
          Type.integer(1),
          Type.consPattern(
            Type.integer(2),
            Type.consPattern(Type.integer(3), Type.list([Type.integer(4)])),
          ),
        );
      });

      it("[1 | [2 | [3 | [4]]]] = [1, 2, 3, 4]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        const result = Interpreter.matchOperator(right, left, vars);

        assert.deepStrictEqual(result, right);
        assert.deepStrictEqual(vars, {a: Type.integer(9)});
      });

      it("[1 | [2 | [3 | [4]]]] = [1, 2, 3 | 4]", () => {
        const right = Type.improperList([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
          Type.integer(4),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });

      it("[1 | [2 | [3 | [4]]]] = [1, 2, 3]", () => {
        const right = Type.list([
          Type.integer(1),
          Type.integer(2),
          Type.integer(3),
        ]);

        assertMatchError(
          () => Interpreter.matchOperator(right, left, vars),
          right,
        );
      });
    });
  });

  describe("float type", () => {
    it("left float == right float", () => {
      // 2.0 = 2.0
      const result = Interpreter.matchOperator(
        Type.float(2.0),
        Type.float(2.0),
        vars,
      );

      assert.deepStrictEqual(result, Type.float(2.0));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left float != right float", () => {
      const myFloat = Type.float(3.0);

      // 2.0 = 3.0
      assertMatchError(
        () => Interpreter.matchOperator(myFloat, Type.float(2.0), vars),
        myFloat,
      );
    });

    it("left float != right non-float", () => {
      const myAtom = Type.atom("abc");

      // 2.0 = :abc
      assertMatchError(
        () => Interpreter.matchOperator(myAtom, Type.float(2.0), vars),
        myAtom,
      );
    });
  });

  describe("integer type", () => {
    it("left integer == right integer", () => {
      // 2 = 2
      const result = Interpreter.matchOperator(
        Type.integer(2),
        Type.integer(2),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(2));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left integer != right integer", () => {
      const myInteger = Type.integer(3);

      // 2 = 3
      assertMatchError(
        () => Interpreter.matchOperator(myInteger, Type.integer(2), vars),
        myInteger,
      );
    });

    it("left integer != right non-integer", () => {
      const myAtom = Type.atom("abc");

      // 2 = :abc
      assertMatchError(
        () => Interpreter.matchOperator(myAtom, Type.integer(2), vars),
        myAtom,
      );
    });
  });

  describe("list type", () => {
    let list1;

    beforeEach(() => {
      list1 = Type.list([Type.integer(1), Type.integer(2)]);
    });

    it("[1, 2] = [1, 2]", () => {
      const result = Interpreter.matchOperator(list1, list1, vars);

      assert.deepStrictEqual(result, list1);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("[1, 2] = [1, 3]", () => {
      const list2 = Type.list([Type.integer(1), Type.integer(3)]);

      assertMatchError(
        () => Interpreter.matchOperator(list2, list1, vars),
        list2,
      );
    });

    it("[1, 2] = [1 | 2]", () => {
      const list2 = Type.improperList([Type.integer(1), Type.integer(2)]);

      assertMatchError(
        () => Interpreter.matchOperator(list2, list1, vars),
        list2,
      );
    });

    it("[1, 2] = :abc", () => {
      const myAtom = Type.atom("abc");

      assertMatchError(
        () => Interpreter.matchOperator(myAtom, list1, vars),
        myAtom,
      );
    });

    it("[] = [1, 2]", () => {
      assertMatchError(
        () => Interpreter.matchOperator(list1, Type.list([]), vars),
        list1,
      );
    });

    it("[1, 2] = []", () => {
      const emptyList = Type.list([]);

      assertMatchError(
        () => Interpreter.matchOperator(emptyList, list1, vars),
        emptyList,
      );
    });

    it("[] = []", () => {
      const emptyList = Type.list([]);
      const result = Interpreter.matchOperator(emptyList, emptyList, vars);

      assert.deepStrictEqual(result, emptyList);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("[x, 2, y] = [1, 2, 3]", () => {
      const left = Type.list([
        Type.variablePattern("x"),
        Type.integer(2),
        Type.variablePattern("y"),
      ]);

      const right = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Interpreter.matchOperator(right, left, vars);
      assert.deepStrictEqual(result, right);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(3),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });
  });

  describe("map type", () => {
    let data;

    beforeEach(() => {
      data = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
      ];
    });

    it("%{x: 1, y: 2} = %{x: 1, y: 2}", () => {
      const left = Type.map(data);
      const right = Type.map(data);

      const result = Interpreter.matchOperator(right, left, vars);

      assert.deepStrictEqual(result, right);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("%{x: 1, y: 2} = %{x: 1, y: 2, z: 3}", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
        [Type.atom("z"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      const result = Interpreter.matchOperator(right, left, vars);

      assert.deepStrictEqual(result, right);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("%{x: 1, y: 2, z: 3} = %{x: 1, y: 2}", () => {
      const data1 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
        [Type.atom("z"), Type.integer(3)],
      ];

      const left = Type.map(data1);
      const right = Type.map(data);

      assertMatchError(
        () => Interpreter.matchOperator(right, left, vars),
        right,
      );
    });

    it("%{x: 1, y: 2} = %{x: 1, y: 3}", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      assertMatchError(
        () => Interpreter.matchOperator(right, left, vars),
        right,
      );
    });

    it("%{x: 1, y: 2} = :abc", () => {
      const left = Type.map(data);
      const right = Type.atom("abc");

      assertMatchError(
        () => Interpreter.matchOperator(right, left, vars),
        right,
      );
    });

    it("%{x: 1, y: 2} = %{}", () => {
      const left = Type.map(data);
      const emptyMap = Type.map([]);

      assertMatchError(
        () => Interpreter.matchOperator(emptyMap, left, vars),
        emptyMap,
      );
    });

    it("%{} = %{x: 1, y: 2}", () => {
      const emptyMap = Type.map([]);
      const right = Type.map(data);
      const result = Interpreter.matchOperator(right, emptyMap, vars);

      assert.deepStrictEqual(result, right);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("%{} = %{}", () => {
      const emptyMap = Type.map([]);
      const result = Interpreter.matchOperator(emptyMap, emptyMap, vars);

      assert.deepStrictEqual(result, emptyMap);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("%{k: x, m: 2, n: z} = %{k: 1, m: 2, n: 3}", () => {
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

      const result = Interpreter.matchOperator(right, left, vars);
      assert.deepStrictEqual(result, right);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        z: Type.integer(3),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });
  });

  it("match placeholder", () => {
    // _var = 2
    const result = Interpreter.matchOperator(
      Type.integer(2),
      Type.matchPlaceholder(),
      vars,
    );

    assert.deepStrictEqual(result, Type.integer(2));
    assert.deepStrictEqual(vars, {a: Type.integer(9)});
  });

  describe("nested match operators", () => {
    it("x = 2 = 2", () => {
      const result = Interpreter.matchOperator(
        Interpreter.matchOperator(
          Type.integer(2),
          Type.integer(2),
          vars,
          false,
        ),
        Type.variablePattern("x"),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("x = 2 = 3", () => {
      const integer3 = Type.integer(3);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(integer3, Type.integer(2), vars, false),
            Type.variablePattern("x"),
            vars,
          ),
        integer3,
      );
    });

    it("2 = x = 2", () => {
      const result = Interpreter.matchOperator(
        Interpreter.matchOperator(
          Type.integer(2),
          Type.variablePattern("x"),
          vars,
          false,
        ),
        Type.integer(2),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("2 = x = 3", () => {
      const integer3 = Type.integer(3);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              integer3,
              Type.variablePattern("x"),
              vars,
              false,
            ),
            Type.integer(2),
            vars,
          ),
        integer3,
      );
    });

    it("2 = 2 = x, (x = 2)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      const result = Interpreter.matchOperator(
        Interpreter.matchOperator(vars.x, Type.integer(2), vars, false),
        Type.integer(2),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("2 = 2 = x, (x = 3)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(3),
      };

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(vars.x, Type.integer(2), vars, false),
            Type.integer(2),
            vars,
          ),
        Type.integer(3),
      );
    });

    it("1 = 2 = x, (x = 2)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(vars.x, Type.integer(2), vars, false),
            Type.integer(1),
            vars,
          ),
        Type.integer(2),
      );
    });

    it("y = x + (x = 3) + x, (x = 11)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(11),
      };

      Interpreter.takeVarsSnapshot(vars);

      const result = Interpreter.matchOperator(
        Erlang["+/2"](
          Erlang["+/2"](
            vars.__snapshot__.x,
            Interpreter.matchOperator(
              Type.integer(3),
              Type.variablePattern("x"),
              vars,
              false,
            ),
          ),
          vars.__snapshot__.x,
        ),
        Type.variablePattern("y"),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(25));

      const expectedVars = {
        __snapshot__: {
          a: Type.integer(9),
          x: Type.integer(11),
        },
        a: Type.integer(9),
        x: Type.integer(3),
        y: Type.integer(25),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[1 = 1] = [1 = 1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([
          Interpreter.matchOperator(
            Type.integer(1),
            Type.integer(1),
            vars,
            false,
          ),
        ]),
        Type.list([
          Interpreter.matchOperator(
            Type.integer(1),
            Type.integer(1),
            vars,
            false,
          ),
        ]),
        vars,
      );

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("[1 = 1] = [1 = 2]", () => {
      const integer2 = Type.integer(2);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(integer2, Type.integer(1), vars, false),
            ]),
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false,
              ),
            ]),
            vars,
          ),
        integer2,
      );
    });

    it("[1 = 1] = [2 = 1]", () => {
      const integer1 = Type.integer(1);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(integer1, Type.integer(2), vars, false),
            ]),
            Type.list([
              Interpreter.matchOperator(integer1, integer1, vars, false),
            ]),
            vars,
          ),
        integer1,
      );
    });

    // TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
    it("[1 = 2] = [1 = 1]", () => {
      const integer2 = Type.integer(2);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false,
              ),
            ]),
            Type.list([
              Interpreter.matchOperator(integer2, Type.integer(1), vars, false),
            ]),
            vars,
          ),
        integer2,
      );
    });

    // TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
    it("[2 = 1] = [1 = 1]", () => {
      const integer1 = Type.integer(1);

      assertMatchError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(integer1, integer1, vars, false),
            ]),
            Type.list([
              Interpreter.matchOperator(integer1, Type.integer(2), vars, false),
            ]),
            vars,
          ),
        integer1,
      );
    });

    it("{a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}", () => {
      const vars = {
        a: Type.integer(9),
        f: Type.integer(3),
      };

      const result = Interpreter.matchOperator(
        Interpreter.matchOperator(
          Type.tuple([
            Type.integer(1),
            Type.integer(2),
            Interpreter.matchOperator(
              vars.f,
              Type.variablePattern("e"),
              vars,
              false,
            ),
          ]),
          Type.tuple([
            Type.integer(1),
            Interpreter.matchOperator(
              Type.variablePattern("d"),
              Type.variablePattern("c"),
              vars,
              false,
            ),
            Type.integer(3),
          ]),
          vars,
          false,
        ),
        Type.tuple([
          Interpreter.matchOperator(
            Type.variablePattern("b"),
            Type.variablePattern("a"),
            vars,
            false,
          ),
          Type.integer(2),
          Type.integer(3),
        ]),
        vars,
      );

      const expectedResult = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(1),
        c: Type.integer(2),
        d: Type.integer(2),
        e: Type.integer(3),
        f: Type.integer(3),
      };

      assert.deepStrictEqual(vars, expectedVars);
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
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.list([Type.integer(2), Type.integer(3)]),
        c: Type.integer(1),
        d: Type.list([Type.integer(2), Type.integer(3)]),
      };

      assert.deepStrictEqual(vars, expectedVars);
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
                vars,
                false,
              ),
            ]),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([
        Type.list([
          Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        ]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.list([Type.integer(2), Type.integer(3)]),
        c: Type.integer(1),
        d: Type.list([Type.integer(2), Type.integer(3)]),
        e: Type.integer(1),
        f: Type.list([Type.integer(2), Type.integer(3)]),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[[a, b] = [c, d]] = [[1, 2]]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
        Type.list([
          Interpreter.matchOperator(
            Type.list([Type.variablePattern("c"), Type.variablePattern("d")]),
            Type.list([Type.variablePattern("a"), Type.variablePattern("b")]),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([
        Type.list([Type.integer(1), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[[[a, b] = [c, d]] = [[e, f]]] = [[[1, 2]]]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.list([Type.list([Type.integer(1), Type.integer(2)])])]),
        Type.list([
          Interpreter.matchOperator(
            Type.list([
              Type.list([Type.variablePattern("e"), Type.variablePattern("f")]),
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
                vars,
                false,
              ),
            ]),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([
        Type.list([Type.list([Type.integer(1), Type.integer(2)])]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
        e: Type.integer(1),
        f: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Type.variablePattern("y"),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[1 = x] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Type.variablePattern("x"),
            Type.integer(1n),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = 1] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Type.integer(1n),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y = z] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("z"),
              Type.variablePattern("y"),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[1 = x = y] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("y"),
              Type.variablePattern("x"),
              vars,
              false,
            ),
            Type.integer(1n),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = 1 = y] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("y"),
              Type.integer(1n),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y = 1] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.integer(1n),
              Type.variablePattern("y"),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[v = x = y = z] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.variablePattern("y"),
                vars,
                false,
              ),
              Type.variablePattern("x"),
              vars,
              false,
            ),
            Type.variablePattern("v"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        v: Type.integer(1),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[1 = x = y = z] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.variablePattern("y"),
                vars,
                false,
              ),
              Type.variablePattern("x"),
              vars,
              false,
            ),
            Type.integer(1n),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = 1 = y = z] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.variablePattern("y"),
                vars,
                false,
              ),
              Type.integer(1n),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y = 1 = z] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.variablePattern("z"),
                Type.integer(1n),
                vars,
                false,
              ),
              Type.variablePattern("y"),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y = z = 1] = [1]", () => {
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1n)]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.integer(1n),
                Type.variablePattern("z"),
                vars,
                false,
              ),
              Type.variablePattern("y"),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(1)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(1),
        z: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("[x = y = z] = [a = b = c = 2]", () => {
      const result = Interpreter.matchOperator(
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Interpreter.matchOperator(
                Type.integer(2n),
                Type.variablePattern("c"),
                vars,
                false,
              ),
              Type.variablePattern("b"),
              vars,
              false,
            ),
            Type.variablePattern("a"),
            vars,
            false,
          ),
        ]),
        Type.list([
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("z"),
              Type.variablePattern("y"),
              vars,
              false,
            ),
            Type.variablePattern("x"),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.list([Type.integer(2)]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(2),
        b: Type.integer(2),
        c: Type.integer(2),
        x: Type.integer(2),
        y: Type.integer(2),
        z: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
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
              vars,
              false,
            ),
          ],
        ]),
        vars,
      );

      const expectedResult = Type.map([
        [
          Type.atom("x"),
          Type.map([
            [Type.atom("a"), Type.integer(1)],
            [Type.atom("b"), Type.integer(2)],
          ]),
        ],
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
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
                    vars,
                    false,
                  ),
                ],
              ]),
              vars,
              false,
            ),
          ],
        ]),
        vars,
      );

      const expectedResult = Type.map([
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
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
        e: Type.integer(1),
        f: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("{{a, b} = {c, d}} = {{1, 2}}", () => {
      const result = Interpreter.matchOperator(
        Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
        Type.tuple([
          Interpreter.matchOperator(
            Type.tuple([Type.variablePattern("c"), Type.variablePattern("d")]),
            Type.tuple([Type.variablePattern("a"), Type.variablePattern("b")]),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.tuple([
        Type.tuple([Type.integer(1), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
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
                vars,
                false,
              ),
            ]),
            vars,
            false,
          ),
        ]),
        vars,
      );

      const expectedResult = Type.tuple([
        Type.tuple([Type.tuple([Type.integer(1), Type.integer(2)])]),
      ]);

      assert.deepStrictEqual(result, expectedResult);

      const expectedVars = {
        a: Type.integer(1),
        b: Type.integer(2),
        c: Type.integer(1),
        d: Type.integer(2),
        e: Type.integer(1),
        f: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });
  });

  describe("tuple type", () => {
    let tuple1;

    beforeEach(() => {
      tuple1 = Type.tuple([Type.integer(1), Type.integer(2)]);
    });

    it("{1, 2} = {1, 2}", () => {
      const result = Interpreter.matchOperator(tuple1, tuple1, vars);

      assert.deepStrictEqual(result, tuple1);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("{1, 2} = {1, 3}", () => {
      const tuple2 = Type.tuple([Type.integer(1), Type.integer(3)]);

      assertMatchError(
        () => Interpreter.matchOperator(tuple2, tuple1, vars),
        tuple2,
      );
    });

    it("{1, 2} = :abc", () => {
      const myAtom = Type.atom("abc");

      assertMatchError(
        () => Interpreter.matchOperator(myAtom, tuple1, vars),
        myAtom,
      );
    });

    it("{} = {1, 2}", () => {
      assertMatchError(
        () => Interpreter.matchOperator(tuple1, Type.tuple([]), vars),
        tuple1,
      );
    });

    it("{1, 2} = {}", () => {
      const emptyTuple = Type.tuple([]);

      assertMatchError(
        () => Interpreter.matchOperator(emptyTuple, tuple1, vars),
        emptyTuple,
      );
    });

    it("{} = {}", () => {
      const emptyTuple = Type.tuple([]);
      const result = Interpreter.matchOperator(emptyTuple, emptyTuple, vars);

      assert.deepStrictEqual(result, emptyTuple);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("{x, 2, y} = {1, 2, 3}", () => {
      const left = Type.tuple([
        Type.variablePattern("x"),
        Type.integer(2),
        Type.variablePattern("y"),
      ]);

      const right = Type.tuple([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Interpreter.matchOperator(right, left, vars);
      assert.deepStrictEqual(result, right);

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
        y: Type.integer(3),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });
  });

  describe("variable pattern", () => {
    it("variable pattern == anything", () => {
      // x = 2
      const result = Interpreter.matchOperator(
        Type.integer(2),
        Type.variablePattern("x"),
        vars,
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("multiple variables with the same name being matched to the same value", () => {
      // [x, x] = [1, 1]
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1), Type.integer(1)]),
        Type.list([Type.variablePattern("x"), Type.variablePattern("x")]),
        vars,
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(1)]),
      );

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("multiple variables with the same name being matched to the different values", () => {
      const right = Type.list([Type.integer(1), Type.integer(2)]);

      // [x, x] = [1, 2]
      assertMatchError(
        () =>
          Interpreter.matchOperator(
            right,
            Type.list([Type.variablePattern("x"), Type.variablePattern("x")]),
            vars,
          ),
        right,
      );
    });
  });
});

it("module()", () => {
  assert.equal(Interpreter.module("maps"), Erlang_Maps);
});

describe("moduleName()", () => {
  describe("boxed alias argument", () => {
    it("Elixir module alias without camel case segments", () => {
      const alias = Type.atom("Elixir.Aaa.Bbb.Ccc");
      const result = Interpreter.moduleName(alias);

      assert.equal(result, "Elixir_Aaa_Bbb_Ccc");
    });

    it("Elixir module alias with camel case segments", () => {
      const alias = Type.atom("Elixir.AaaBbb.CccDdd");
      const result = Interpreter.moduleName(alias);

      assert.equal(result, "Elixir_AaaBbb_CccDdd");
    });

    it(":erlang alias", () => {
      const alias = Type.atom("erlang");
      const result = Interpreter.moduleName(alias);

      assert.equal(result, "Erlang");
    });

    it("single-segment Erlang module alias", () => {
      const alias = Type.atom("aaa");
      const result = Interpreter.moduleName(alias);

      assert.equal(result, "Erlang_Aaa");
    });

    it("multiple-segment Erlang module alias", () => {
      const alias = Type.atom("aaa_bbb");
      const result = Interpreter.moduleName(alias);

      assert.equal(result, "Erlang_Aaa_Bbb");
    });
  });

  describe("JS string argument", () => {
    it("Elixir module alias without camel case segments", () => {
      const result = Interpreter.moduleName("Elixir.Aaa.Bbb.Ccc");
      assert.equal(result, "Elixir_Aaa_Bbb_Ccc");
    });

    it("Elixir module alias with camel case segments", () => {
      const result = Interpreter.moduleName("Elixir.AaaBbb.CccDdd");
      assert.equal(result, "Elixir_AaaBbb_CccDdd");
    });

    it(":erlang alias", () => {
      const result = Interpreter.moduleName("erlang");
      assert.equal(result, "Erlang");
    });

    it("single-segment Erlang module alias", () => {
      const result = Interpreter.moduleName("aaa");
      assert.equal(result, "Erlang_Aaa");
    });

    it("multiple-segment Erlang module alias", () => {
      const result = Interpreter.moduleName("aaa_bbb");
      assert.equal(result, "Erlang_Aaa_Bbb");
    });
  });
});

it("raiseArgumentError()", () => {
  assertBoxedError(
    () => Interpreter.raiseArgumentError("abc"),
    "ArgumentError",
    "abc",
  );
});

it("raiseBadMapError()", () => {
  assertBoxedError(
    () => Interpreter.raiseBadMapError(Type.atom("abc")),
    "BadMapError",
    "expected a map, got: :abc",
  );
});

it("raiseCompileError()", () => {
  assertBoxedError(
    () => Interpreter.raiseCompileError("abc"),
    "CompileError",
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

it("raiseKeyError()", () => {
  assertBoxedError(() => Interpreter.raiseKeyError("abc"), "KeyError", "abc");
});

it("raiseMatchError()", () => {
  assertBoxedError(
    () => Interpreter.raiseMatchError(Type.atom("abc")),
    "MatchError",
    "no match of right hand side value: :abc",
  );
});

describe("serialize()", () => {
  it("serializes number to JSON", () => {
    assert.equal(Interpreter.serialize(123), "123");
  });

  it("serializes string to JSON", () => {
    assert.equal(Interpreter.serialize("abc"), '"abc"');
  });

  it("serializes non-negative bigint to JSON", () => {
    assert.equal(Interpreter.serialize(123n), '"__bigint__:123"');
  });

  it("serializes negative bigint to JSON", () => {
    assert.equal(Interpreter.serialize(-123n), '"__bigint__:-123"');
  });

  it("serializes non-nested object to JSON", () => {
    assert.equal(Interpreter.serialize({a: 1, b: 2}), '{"a":1,"b":2}');
  });

  it("serializes nested object to JSON", () => {
    const term = {a: 1, b: 2, c: {d: 3, e: 4}};
    const expected = '{"a":1,"b":2,"c":{"d":3,"e":4}}';

    assert.equal(Interpreter.serialize(term), expected);
  });
});

describe("takeVarsSnapshot()", () => {
  let expected;

  beforeEach(() => {
    expected = {
      __snapshot__: {a: Type.integer(1), b: Type.integer(2)},
      a: Type.integer(1),
      b: Type.integer(2),
    };
  });

  it("when snapshot hasn't been taken yet", () => {
    const vars = {a: Type.integer(1), b: Type.integer(2)};
    Interpreter.takeVarsSnapshot(vars);

    assert.deepStrictEqual(vars, expected);
  });

  it("when snapshot has already been taken", () => {
    const vars = {
      __snapshot__: "dummy",
      a: Type.integer(1),
      b: Type.integer(2),
    };

    Interpreter.takeVarsSnapshot(vars);

    assert.deepStrictEqual(vars, expected);
  });
});

describe("try()", () => {
  let vars;

  beforeEach(() => {
    vars = {
      a: Type.integer(1),
      b: Type.integer(2),
    };
  });

  it("body without any errors, throws or exists / vars are not mutated in body", () => {
    // try do
    //   a = 3
    //   :ok
    // end
    const body = (vars) => {
      Interpreter.matchOperator(
        Type.integer(3n),
        Type.variablePattern("a"),
        vars,
      );
      return Type.atom("ok");
    };

    const result = Interpreter.try(body, [], [], [], null, vars);

    assert.deepStrictEqual(result, Type.atom("ok"));
    assert.deepStrictEqual(vars.a, Type.integer(1));
  });
});

// TODO: finish implementing
it("with()", () => {
  assert.throw(
    () => Interpreter.with(),
    Error,
    '"with" expression is not yet implemented in Hologram',
  );
});
