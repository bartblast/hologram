"use strict";

import {
  assert,
  assertError,
  linkModules,
  sinon,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Erlang from "../../assets/js/erlang/erlang.mjs";
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
          params: [Type.integer(1)],
          guard: null,
          body: (_vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.integer(2)],
          guard: null,
          body: (_vars) => {
            return Type.atom("expr_2");
          },
        },
      ],
      vars
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
          params: [Type.variablePattern("x")],
          guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.variablePattern("y")],
          guard: (vars) => Erlang.$261$261(vars.y, Type.integer(2)),
          body: (vars) => {
            return Type.atom("expr_2");
          },
        },
        {
          params: [Type.variablePattern("z")],
          guard: (vars) => Erlang.$261$261(vars.z, Type.integer(3)),
          body: (vars) => {
            return Type.atom("expr_3");
          },
        },
      ],
      vars
    );

    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(3),
    ]);

    assert.deepStrictEqual(result, Type.atom("expr_3"));
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
          params: [Type.variablePattern("x"), Type.integer(1)],
          guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.variablePattern("y"), Type.integer(2)],
          guard: null,
          body: (vars) => {
            return vars.x;
          },
        },
      ],
      vars
    );

    const result = Interpreter.callAnonymousFunction(anonFun, [
      Type.integer(2),
      Type.integer(2),
    ]);

    assert.deepStrictEqual(result, Type.integer(9));
  });

  it("raises FunctionClauseError error if none of the clauses is matched", () => {
    assertError(
      () => Interpreter.callAnonymousFunction(anonFun, [Type.integer(3)]),
      "FunctionClauseError",
      "no function clause matching in anonymous fn/1"
    );
  });
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
      head: Type.integer(1),
      guard: null,
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      head: Type.integer(2),
      guard: null,
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      head: Type.integer(3),
      guard: null,
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const result = Interpreter.case(
      Type.integer(2),
      [clause1, clause2, clause3],
      vars
    );

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("runs guards for each tried clause", () => {
    // case 2 do
    //   x when x == 1 -> :expr_1
    //   y when y == 1 -> :expr_2
    //   z when z == 3 -> :expr_3
    // end

    const clause1 = {
      head: Type.variablePattern("x"),
      guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      head: Type.variablePattern("y"),
      guard: (vars) => Erlang.$261$261(vars.y, Type.integer(2)),
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      head: Type.variablePattern("z"),
      guard: (vars) => Erlang.$261$261(vars.z, Type.integer(3)),
      body: (_vars) => {
        return Type.atom("expr_3");
      },
    };

    const result = Interpreter.case(
      Type.integer(2),
      [clause1, clause2, clause3],
      vars
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
      head: Type.variablePattern("x"),
      guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      head: Type.variablePattern("y"),
      guard: null,
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
      head: Type.integer(1),
      guard: null,
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      head: Type.integer(2),
      guard: null,
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    assertError(
      () => Interpreter.case(Type.integer(3), [clause1, clause2], vars),
      "CaseClauseError",
      "no case clause matching: 3"
    );
  });
});

describe("comprehension()", () => {
  let vars, prevIntoFun, prevToListFun;

  beforeEach(() => {
    vars = {a: Type.integer(1), b: Type.integer(2)};

    prevIntoFun = globalThis.Elixir_Enum.into;

    globalThis.Elixir_Enum.into = (enumerable, _collectable) => {
      return enumerable;
    };

    prevToListFun = globalThis.Elixir_Enum.to_list;

    globalThis.Elixir_Enum.to_list = (enumerable) => {
      return enumerable;
    };
  });

  afterEach(() => {
    globalThis.Elixir_Enum.into = prevIntoFun;
    globalThis.Elixir_Enum.to_list = prevToListFun;
  });

  describe("generator", () => {
    it("generates combinations of enumerables items", () => {
      // for x <- [1, 2], y <- [3, 4], do: {x, y}

      const generator1 = {
        enumerable: Type.list([Type.integer(1), Type.integer(2)]),
        match: Type.variablePattern("x"),
        guard: null,
      };

      const generator2 = {
        enumerable: Type.list([Type.integer(3), Type.integer(4)]),
        match: Type.variablePattern("y"),
        guard: null,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
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

      const enumerable1 = Type.list([
        Type.integer(1),
        Type.tuple([Type.integer(11), Type.integer(2)]),
        Type.integer(3),
        Type.tuple([Type.integer(11), Type.integer(4)]),
      ]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.tuple([Type.integer(11), Type.variablePattern("x")]),
        guard: null,
      };

      const enumerable2 = Type.list([
        Type.integer(5),
        Type.tuple([Type.integer(12), Type.integer(6)]),
        Type.integer(7),
        Type.tuple([Type.integer(12), Type.integer(8)]),
      ]);

      const generator2 = {
        enumerable: enumerable2,
        match: Type.tuple([Type.integer(12), Type.variablePattern("y")]),
        guard: null,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
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

      const enumerable1 = Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const enumerable2 = Type.list([Type.integer(3), Type.integer(4)]);

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: null,
      };

      const stub = sinon
        .stub(Elixir_Enum, "to_list")
        .callsFake((enumerable) => enumerable);

      Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
      );

      sinon.assert.calledWith(stub, enumerable1);
      sinon.assert.calledWith(stub, enumerable2);
    });
  });

  describe("guards", () => {
    it("are applied", () => {
      // for x when x != 2 <- [1, 2, 3],
      //     y when y != 4 <- [4, 5, 6],
      //     do: {x, y}
      //
      // for x when :erlang."/="(x, 2) <- [1, 2, 3],
      //     y when :erlang."/="(y, 4) <- [4, 5, 6],
      //     do: {x, y}

      const enumerable1 = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const guard1 = (vars) => Erlang.$247$261(vars.x, Type.integer(2));

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: guard1,
      };

      const enumerable2 = Type.list([
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
      ]);

      const guard2 = (vars) => Erlang.$247$261(vars.y, Type.integer(4));

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: guard2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
      );

      const expected = Type.list([
        Type.tuple([Type.integer(1), Type.integer(5)]),
        Type.tuple([Type.integer(1), Type.integer(6)]),
        Type.tuple([Type.integer(3), Type.integer(5)]),
        Type.tuple([Type.integer(3), Type.integer(6)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("can access variables from comprehension outer scope", () => {
      // for x when x != b <- [1, 2, 3], do: x

      const enumerable = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const guard = (vars) => Erlang.$247$261(vars.x, vars.b);

      const generator = {
        enumerable: enumerable,
        match: Type.variablePattern("x"),
        guard: guard,
      };

      const result = Interpreter.comprehension(
        [generator],
        [],
        Type.list([]),
        false,
        (vars) => vars.x,
        vars
      );

      const expected = Type.list([Type.integer(1), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });

    it("can access variables pattern matched in preceding guards", () => {
      // for x <- [1, 2], y when x != 1 <- [3, 4], do: {x, y}

      const enumerable1 = Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const enumerable2 = Type.list([Type.integer(3), Type.integer(4)]);

      const guard2 = (vars) => Erlang.$247$261(vars.x, Type.integer(1));

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: guard2,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
      );

      const expected = Type.list([
        Type.tuple([Type.integer(2), Type.integer(3)]),
        Type.tuple([Type.integer(2), Type.integer(4)]),
      ]);

      assert.deepStrictEqual(result, expected);
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

      const enumerable1 = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const enumerable2 = Type.list([
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
      ]);

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: null,
      };

      const filters = [
        (vars) => Erlang.$260(Erlang.$243(vars.x, vars.y), Type.integer(8)),
        (vars) => Erlang.$262(Erlang.$245(vars.y, vars.x), Type.integer(2)),
      ];

      const result = Interpreter.comprehension(
        [generator1, generator2],
        filters,
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
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

      const enumerable = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const generator = {
        enumerable: enumerable,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const filter = (vars) => Erlang.$247$261(vars.x, vars.b);

      const result = Interpreter.comprehension(
        [generator],
        [filter],
        Type.list([]),
        false,
        (vars) => vars.x,
        vars
      );

      const expected = Type.list([Type.integer(1), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("unique", () => {
    it("non-unique items are removed if 'uniq' option is set to true", () => {
      // for x <- [1, 2, 1], y <- [3, 4, 3], do: {x, y}

      const enumerable1 = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(1),
      ]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const enumerable2 = Type.list([
        Type.integer(3),
        Type.integer(4),
        Type.integer(3),
      ]);

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: null,
      };

      const result = Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.list([]),
        true,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
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

      const enumerable = Type.list([Type.integer(1), Type.integer(2)]);

      const generator = {
        enumerable: enumerable,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const result = Interpreter.comprehension(
        [generator],
        [],
        Type.list([]),
        false,
        (vars) => Type.tuple([vars.x, vars.b]),
        vars
      );

      const expected = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.tuple([Type.integer(2), Type.integer(2)]),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("uses Enum.into/2 to insert the comprehension result into a collectable", () => {
      // for x <- [1, 2], y <- [3, 4], do: {x, y}

      const enumerable1 = Type.list([Type.integer(1), Type.integer(2)]);

      const generator1 = {
        enumerable: enumerable1,
        match: Type.variablePattern("x"),
        guard: null,
      };

      const enumerable2 = Type.list([Type.integer(3), Type.integer(4)]);

      const generator2 = {
        enumerable: enumerable2,
        match: Type.variablePattern("y"),
        guard: null,
      };

      const stub = sinon
        .stub(Elixir_Enum, "into")
        .callsFake((enumerable) => enumerable);

      Interpreter.comprehension(
        [generator1, generator2],
        [],
        Type.map([]),
        false,
        (vars) => Type.tuple([vars.x, vars.y]),
        vars
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
          vars
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

    assertError(
      () => Interpreter.cond([clause1, clause2], vars),
      "CondClauseError",
      "no cond clause evaluated to a truthy value"
    );
  });
});

describe("consOperator()", () => {
  it("prepends left boxed item to the right boxed list", () => {
    const left = Type.integer(1);
    const right = Type.list([Type.integer(2), Type.integer(3)]);
    const result = Interpreter.consOperator(left, right);

    const expected = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);

    assert.deepStrictEqual(result, expected);
  });
});

describe("defineFunction()", () => {
  beforeEach(() => {
    // def my_fun_a(1), do: :expr_1
    // def my_fun_a(2), do: :expr_2
    Interpreter.defineFunction("Elixir_Aaa_Bbb", "my_fun_a", [
      {
        params: [Type.integer(1)],
        guard: null,
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: [Type.integer(2)],
        guard: null,
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
    Interpreter.defineFunction("Elixir_Ddd", "my_fun_d", []);

    assert.isTrue(globalThis.hasOwnProperty("Elixir_Ddd"));
    assert.isTrue(globalThis.Elixir_Ddd.hasOwnProperty("my_fun_d"));

    // cleanup
    delete globalThis.Elixir_Ddd;
  });

  it("appends to the module global var if it is already initiated", () => {
    globalThis.Elixir_Eee = {dummy: "dummy"};
    Interpreter.defineFunction("Elixir_Eee", "my_fun_e", []);

    assert.isTrue(globalThis.hasOwnProperty("Elixir_Eee"));
    assert.isTrue(globalThis.Elixir_Eee.hasOwnProperty("my_fun_e"));
    assert.equal(globalThis.Elixir_Eee.dummy, "dummy");

    // cleanup
    delete globalThis.Elixir_Eee;
  });

  it("defines function which runs the first matching clause", () => {
    const result = globalThis.Elixir_Aaa_Bbb.my_fun_a(Type.integer(1));
    assert.deepStrictEqual(result, Type.atom("expr_1"));
  });

  it("defines function which ignores not matching clauses", () => {
    const result = globalThis.Elixir_Aaa_Bbb.my_fun_a(Type.integer(2));
    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("defines function which runs guards for each tried clause", () => {
    // def my_fun_b(x) when x == 1, do: :expr_1
    // def my_fun_b(y) when y == 2, do: :expr_2
    // def my_fun_b(z) when z == 3, do: :expr_3
    Interpreter.defineFunction("Elixir_Aaa_Bbb", "my_fun_b", [
      {
        params: [Type.variablePattern("x")],
        guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: [Type.variablePattern("y")],
        guard: (vars) => Erlang.$261$261(vars.y, Type.integer(2)),
        body: (_vars) => {
          return Type.atom("expr_2");
        },
      },
      {
        params: [Type.variablePattern("z")],
        guard: (vars) => Erlang.$261$261(vars.z, Type.integer(3)),
        body: (_vars) => {
          return Type.atom("expr_3");
        },
      },
    ]);

    const result = globalThis.Elixir_Aaa_Bbb.my_fun_b(Type.integer(3));

    assert.deepStrictEqual(result, Type.atom("expr_3"));
  });

  it("defines function which clones vars for each clause", () => {
    // def my_fun_c(x) when x == 1, do: :expr_1
    // def my_fun_c(x) when x == 2, do: :expr_2
    Interpreter.defineFunction("Elixir_Aaa_Bbb", "my_fun_c", [
      {
        params: [Type.variablePattern("x")],
        guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1)),
        body: (_vars) => {
          return Type.atom("expr_1");
        },
      },
      {
        params: [Type.variablePattern("x")],
        guard: (vars) => Erlang.$261$261(vars.x, Type.integer(2)),
        body: (_vars) => {
          return Type.atom("expr_2");
        },
      },
    ]);

    const result = globalThis.Elixir_Aaa_Bbb.my_fun_c(Type.integer(2));

    assert.deepStrictEqual(result, Type.atom("expr_2"));
  });

  it("raises UndefinedFunctionError if there are no clauses with the same arity", () => {
    assertError(
      () =>
        globalThis.Elixir_Aaa_Bbb.my_fun_a(Type.integer(1), Type.integer(2)),
      "UndefinedFunctionError",
      "function Aaa.Bbb.my_fun_a/2 is undefined or private"
    );
  });

  it("raises FunctionClauseError if there are clauses with the same arity but none of them is matched", () => {
    assertError(
      () => globalThis.Elixir_Aaa_Bbb.my_fun_a(Type.integer(3)),
      "FunctionClauseError",
      "no function clause matching in Aaa.Bbb.my_fun_a/1"
    );
  });
});

describe("dotOperator()", () => {
  it("handles remote function call", () => {
    // setup
    globalThis.Elixir_MyModule = {
      my_fun: () => {
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

describe("isStrictlyEqual()", () => {
  it("returns true if the args are of the same boxed primitive type and have equal values", () => {
    const result = Interpreter.isStrictlyEqual(
      Type.integer(1),
      Type.integer(1)
    );

    assert.isTrue(result);
  });

  it("returns false if the args are not of the same boxed primitive type but have equal values", () => {
    const result = Interpreter.isStrictlyEqual(
      Type.integer(1),
      Type.float(1.0)
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
        vars
      );

      assert.deepStrictEqual(result, Type.atom("abc"));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left atom != right atom", () => {
      // :abc = :xyz
      assertError(
        () =>
          Interpreter.matchOperator(Type.atom("xyz"), Type.atom("abc"), vars),
        "MatchError",
        "no match of right hand side value: :xyz"
      );
    });

    it("left atom != right non-atom", () => {
      // :abc = 2
      assertError(
        () =>
          Interpreter.matchOperator(Type.integer(2), Type.atom("abc"), vars),
        "MatchError",
        "no match of right hand side value: 2"
      );
    });
  });

  describe("cons pattern", () => {
    it("left cons pattern == right list, cons pattern head and tail are variables", () => {
      // [h | t] = [1, 2, 3]
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.consPattern(Type.variablePattern("h"), Type.variablePattern("t")),
        vars
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
      );

      assert.deepStrictEqual(vars, {
        a: Type.integer(9),
        h: Type.integer(1),
        t: Type.list([Type.integer(2), Type.integer(3)]),
      });
    });

    it("left cons pattern == right list, cons pattern head is variable, tail is literal", () => {
      // [h | [2, 3]] = [1, 2, 3]
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.consPattern(
          Type.variablePattern("h"),
          Type.list([Type.integer(2), Type.integer(3)])
        ),
        vars
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
      );

      assert.deepStrictEqual(vars, {
        a: Type.integer(9),
        h: Type.integer(1),
      });
    });

    it("left cons pattern == right list, cons pattern head is literal, tail is variable", () => {
      // [1 | t] = [1, 2, 3]
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.consPattern(Type.integer(1), Type.variablePattern("t")),
        vars
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
      );

      assert.deepStrictEqual(vars, {
        a: Type.integer(9),
        t: Type.list([Type.integer(2), Type.integer(3)]),
      });
    });

    it("left cons pattern == right list, cons pattern head and tail are literals", () => {
      // [1 | [2, 3]] = [1, 2, 3]
      const result = Interpreter.matchOperator(
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
        Type.consPattern(
          Type.integer(1),
          Type.list([Type.integer(2), Type.integer(3)])
        ),
        vars
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(2), Type.integer(3)])
      );

      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("raises match error if right is not a list", () => {
      // [h | t] = 123
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.integer(123),
            Type.consPattern(
              Type.variablePattern("h"),
              Type.variablePattern("t")
            ),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 123"
      );
    });

    it("raises match error if right is an empty list", () => {
      // [h | t] = []
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([]),
            Type.consPattern(
              Type.variablePattern("h"),
              Type.variablePattern("t")
            ),
            vars
          ),
        "MatchError",
        "no match of right hand side value: []"
      );
    });

    it("raises match error if head doesn't match", () => {
      // [4 | [2, 3]] = [1, 2, 3]
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
            Type.consPattern(
              Type.integer(4),
              Type.list([Type.integer(2), Type.integer(3)])
            ),
            vars
          ),
        "MatchError",
        "no match of right hand side value: [1, 2, 3]"
      );
    });

    it("raises match error if tail doesn't match", () => {
      // [1 | [4, 3]] = [1, 2, 3]
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]),
            Type.consPattern(
              Type.integer(1),
              Type.list([Type.integer(4), Type.integer(3)])
            ),
            vars
          ),
        "MatchError",
        "no match of right hand side value: [1, 2, 3]"
      );
    });
  });

  describe("float type", () => {
    it("left float == right float", () => {
      // 2.0 = 2.0
      const result = Interpreter.matchOperator(
        Type.float(2.0),
        Type.float(2.0),
        vars
      );

      assert.deepStrictEqual(result, Type.float(2.0));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left float != right float", () => {
      // 2.0 = 3.0
      assertError(
        () => Interpreter.matchOperator(Type.float(3.0), Type.float(2.0), vars),
        "MatchError",
        "no match of right hand side value: 3.0"
      );
    });

    it("left float != right non-float", () => {
      // 2.0 = :abc
      assertError(
        () =>
          Interpreter.matchOperator(Type.atom("abc"), Type.float(2.0), vars),
        "MatchError",
        "no match of right hand side value: :abc"
      );
    });
  });

  describe("integer type", () => {
    it("left integer == right integer", () => {
      // 2 = 2
      const result = Interpreter.matchOperator(
        Type.integer(2),
        Type.integer(2),
        vars
      );

      assert.deepStrictEqual(result, Type.integer(2));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left integer != right integer", () => {
      // 2 = 3
      assertError(
        () => Interpreter.matchOperator(Type.integer(3), Type.integer(2), vars),
        "MatchError",
        "no match of right hand side value: 3"
      );
    });

    it("left integer != right non-integer", () => {
      // 2 = :abc
      assertError(
        () =>
          Interpreter.matchOperator(Type.atom("abc"), Type.integer(2), vars),
        "MatchError",
        "no match of right hand side value: :abc"
      );
    });
  });

  describe("list type", () => {
    let list1;

    beforeEach(() => {
      list1 = Type.list([Type.integer(1), Type.integer(2)]);
    });

    it("left list == right list", () => {
      // [1, 2] = [1, 2]
      const result = Interpreter.matchOperator(list1, list1, vars);

      assert.deepStrictEqual(result, list1);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left list != right list", () => {
      const list2 = Type.list([Type.integer(1), Type.integer(3)]);

      // [1, 2] = [1, 3]
      assertError(
        () => Interpreter.matchOperator(list2, list1, vars),
        "MatchError",
        "no match of right hand side value: [1, 3]"
      );
    });

    it("left list != right non-list", () => {
      // [1, 2] = :abc
      assertError(
        () => Interpreter.matchOperator(Type.atom("abc"), list1, vars),
        "MatchError",
        "no match of right hand side value: :abc"
      );
    });

    it("left list has variables", () => {
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

      // [x, 2, y] = [1, 2, 3]
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

    it("left and right maps have the same items", () => {
      const left = Type.map(data);
      const right = Type.map(data);

      // %{x: 1, y: 2} = %{x: 1, y: 2}
      const result = Interpreter.matchOperator(right, left, vars);

      assert.deepStrictEqual(result, right);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("right map have all the same items as the left map plus additional ones", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
        [Type.atom("z"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      // %{x: 1, y: 2} = %{x: 1, y: 2, z: 3}
      const result = Interpreter.matchOperator(right, left, vars);

      assert.deepStrictEqual(result, right);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("right map is missing some some keys from the left map", () => {
      const data1 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(2)],
        [Type.atom("z"), Type.integer(3)],
      ];

      const left = Type.map(data1);
      const right = Type.map(data);

      // %{x: 1, y: 2, z: 3} = %{x: 1, y: 2}
      assertError(
        () => Interpreter.matchOperator(right, left, vars),
        "MatchError",
        'no match of right hand side value: {"type":"map","data":{"atom(x)":[{"type":"atom","value":"x"},{"type":"integer","value":"__bigint__:1"}],"atom(y)":[{"type":"atom","value":"y"},{"type":"integer","value":"__bigint__:2"}]}}'
      );
    });

    it("some left map item values don't match right map item values", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("x"), Type.integer(1)],
        [Type.atom("y"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      // %{x: 1, y: 2} = %{x: 1, y: 3}
      assertError(
        () => Interpreter.matchOperator(right, left, vars),
        "MatchError",
        'no match of right hand side value: {"type":"map","data":{"atom(x)":[{"type":"atom","value":"x"},{"type":"integer","value":"__bigint__:1"}],"atom(y)":[{"type":"atom","value":"y"},{"type":"integer","value":"__bigint__:3"}]}}'
      );
    });

    it("left map != right non-map", () => {
      const left = Type.map(data);
      const right = Type.atom("abc");

      // %{x: 1, y: 2} = :abc
      assertError(
        () => Interpreter.matchOperator(right, left, vars),
        "MatchError",
        "no match of right hand side value: :abc"
      );
    });

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

      // %{k: x, m: 2, n: z} = %{k: 1, m: 2, n: 3}
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
      vars
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
          false
        ),
        Type.variablePattern("x"),
        vars
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("x = 2 = 3", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.integer(3),
              Type.integer(2),
              vars,
              false
            ),
            Type.variablePattern("x"),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 3"
      );
    });

    it("2 = x = 2", () => {
      const result = Interpreter.matchOperator(
        Interpreter.matchOperator(
          Type.integer(2),
          Type.variablePattern("x"),
          vars,
          false
        ),
        Type.integer(2),
        vars
      );

      assert.deepStrictEqual(result, Type.integer(2));

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("2 = x = 3", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.integer(3),
              Type.variablePattern("x"),
              vars,
              false
            ),
            Type.integer(2),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 3"
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
        vars
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

      assertError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(vars.x, Type.integer(2), vars, false),
            Type.integer(2),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 3"
      );
    });

    it("1 = 2 = x, (x = 2)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(2),
      };

      assertError(
        () =>
          Interpreter.matchOperator(
            Interpreter.matchOperator(vars.x, Type.integer(2), vars, false),
            Type.integer(1),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 2"
      );
    });

    it("y = x + (x = 3) + x, (x = 11)", () => {
      const vars = {
        a: Type.integer(9),
        x: Type.integer(11),
      };

      Interpreter.takeVarsSnapshot(vars);

      const result = Interpreter.matchOperator(
        Erlang.$243(
          Erlang.$243(
            vars.__snapshot__.x,
            Interpreter.matchOperator(
              Type.integer(3),
              Type.variablePattern("x"),
              vars,
              false
            )
          ),
          vars.__snapshot__.x
        ),
        Type.variablePattern("y"),
        vars
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
            false
          ),
        ]),
        Type.list([
          Interpreter.matchOperator(
            Type.integer(1),
            Type.integer(1),
            vars,
            false
          ),
        ]),
        vars
      );

      assert.deepStrictEqual(result, Type.list([Type.integer(1)]));
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("[1 = 1] = [1 = 2]", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(
                Type.integer(2),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 2"
      );
    });

    it("[1 = 1] = [2 = 1]", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(2),
                vars,
                false
              ),
            ]),
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 1"
      );
    });

    // TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
    it("[1 = 2] = [1 = 1]", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            Type.list([
              Interpreter.matchOperator(
                Type.integer(2),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 2"
      );
    });

    // TODO: JavaScript error message for this case is inconsistent with Elixir error message (see test/elixir/hologram/ex_js_consistency/match_operator_test.exs)
    it("[2 = 1] = [1 = 1]", () => {
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(1),
                vars,
                false
              ),
            ]),
            Type.list([
              Interpreter.matchOperator(
                Type.integer(1),
                Type.integer(2),
                vars,
                false
              ),
            ]),
            vars
          ),
        "MatchError",
        "no match of right hand side value: 1"
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
            Type.integer(1n),
            Type.integer(2n),
            Interpreter.matchOperator(
              vars.f,
              Type.variablePattern("e"),
              vars,
              false
            ),
          ]),
          Type.tuple([
            Type.integer(1n),
            Interpreter.matchOperator(
              Type.variablePattern("d"),
              Type.variablePattern("c"),
              vars,
              false
            ),
            Type.integer(3n),
          ]),
          vars,
          false
        ),
        Type.tuple([
          Interpreter.matchOperator(
            Type.variablePattern("b"),
            Type.variablePattern("a"),
            vars,
            false
          ),
          Type.integer(2n),
          Type.integer(3n),
        ]),
        vars
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

  describe("tuple type", () => {
    let tuple1;

    beforeEach(() => {
      tuple1 = Type.tuple([Type.integer(1), Type.integer(2)]);
    });

    it("left tuple == right tuple", () => {
      // {1, 2} = {1, 2}
      const result = Interpreter.matchOperator(tuple1, tuple1, vars);

      assert.deepStrictEqual(result, tuple1);
      assert.deepStrictEqual(vars, {a: Type.integer(9)});
    });

    it("left tuple != right tuple", () => {
      const tuple2 = Type.tuple([Type.integer(1), Type.integer(3)]);

      // {1, 2} = {1, 3}
      assertError(
        () => Interpreter.matchOperator(tuple2, tuple1, vars),
        "MatchError",
        "no match of right hand side value: {1, 3}"
      );
    });

    it("left tuple != right non-tuple", () => {
      // {1, 2} = :abc
      assertError(
        () => Interpreter.matchOperator(Type.atom("abc"), tuple1, vars),
        "MatchError",
        "no match of right hand side value: :abc"
      );
    });

    it("left tuple has variables", () => {
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

      // {x, 2, y} = {1, 2, 3}
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
        vars
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
        vars
      );

      assert.deepStrictEqual(
        result,
        Type.list([Type.integer(1), Type.integer(1)])
      );

      const expectedVars = {
        a: Type.integer(9),
        x: Type.integer(1),
      };

      assert.deepStrictEqual(vars, expectedVars);
    });

    it("multiple variables with the same name being matched to the different values", () => {
      // [x, x] = [1, 2]
      assertError(
        () =>
          Interpreter.matchOperator(
            Type.list([Type.integer(1), Type.integer(2)]),
            Type.list([Type.variablePattern("x"), Type.variablePattern("x")]),
            vars
          ),
        "MatchError",
        "no match of right hand side value: [1, 2]"
      );
    });
  });
});

it("raiseMatchError()", () => {
  assertError(
    () => Interpreter.raiseMatchError(Type.atom("abc")),
    "MatchError",
    "no match of right hand side value: :abc"
  );
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
