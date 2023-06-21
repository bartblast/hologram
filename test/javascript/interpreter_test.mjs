"use strict";

import {
  assert,
  assertError,
  assertNotFrozen,
  linkModules,
  sinon,
  unlinkModules,
} from "../../assets/js/test_support.mjs";
import Erlang from "../../assets/js/erlang/erlang.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

// TODO: remove if unused
import Utils from "../../assets/js/utils.mjs";

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
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.integer(2)],
          guard: null,
          body: (vars) => {
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
          guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1n)),
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.variablePattern("y")],
          guard: (vars) => Erlang.$261$261(vars.y, Type.integer(2n)),
          body: (vars) => {
            return Type.atom("expr_2");
          },
        },
        {
          params: [Type.variablePattern("z")],
          guard: (vars) => Erlang.$261$261(vars.z, Type.integer(3n)),
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
          params: [Type.variablePattern("x"), Type.integer(1n)],
          guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1n)),
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.variablePattern("y"), Type.integer(2n)],
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
      guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1n)),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      head: Type.variablePattern("y"),
      guard: (vars) => Erlang.$261$261(vars.y, Type.integer(2n)),
      body: (_vars) => {
        return Type.atom("expr_2");
      },
    };

    const clause3 = {
      head: Type.variablePattern("z"),
      guard: (vars) => Erlang.$261$261(vars.z, Type.integer(3n)),
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
      guard: (vars) => Erlang.$261$261(vars.x, Type.integer(1n)),
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
  let vars;

  beforeEach(() => {
    vars = {a: Type.integer(1), b: Type.integer(2)};

    Interpreter._moduleEnum = class Elixir_Enum {
      static into(enumerable, _collectable) {
        return enumerable;
      }

      static to_list(enumerable) {
        return enumerable;
      }
    };
  });

  afterEach(() => {
    Interpreter._moduleEnum = null;
  });

  describe("generator", () => {
    it("generates combinations of enumerables items", () => {
      // for x <- [1, 2], y <- [3, 4], do: {x, y}

      const generator1 = {
        enumerable: Type.list([Type.integer(1n), Type.integer(2n)]),
        match: Type.variablePattern("x"),
        guard: null,
      };

      const generator2 = {
        enumerable: Type.list([Type.integer(3n), Type.integer(4n)]),
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
        .stub(Interpreter._moduleEnum, "to_list")
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
        (vars) => Erlang.$260(Erlang.$243(vars.x, vars.y), Type.integer(8n)),
        (vars) => Erlang.$262(Erlang.$245(vars.y, vars.x), Type.integer(2n)),
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
        .stub(Interpreter._moduleEnum, "into")
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
          Type.variablePattern("x"),
          Type.boolean(false),
          vars
        ),
      body: (_vars) => {
        return Type.atom("expr_1");
      },
    };

    const clause2 = {
      condition: (vars) => Type.boolean(true),
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

describe("count()", () => {
  it("returns the number of items in a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Interpreter.count(list);

    assert.equal(result, 2);
  });

  it("returns the number of items in a boxed map", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Interpreter.count(map);

    assert.equal(result, 2);
  });

  it("returns the number of items in a boxed tuple", () => {
    const tuple = Type.tuple([Type.integer(1), Type.integer(2)]);
    const result = Interpreter.count(tuple);

    assert.equal(result, 2);
  });
});

describe("head()", () => {
  it("returns the first item in a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Interpreter.head(list);

    assert.deepStrictEqual(result, Type.integer(1));
  });
});

describe("isMatched()", () => {
  describe("atom type", () => {
    it("is matching another boxed atom having the same value", () => {
      const left = Type.atom("abc");
      const right = Type.atom("abc");

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed atom having a different value", () => {
      const left = Type.atom("abc");
      const right = Type.atom("xyz");

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-atom boxed type", () => {
      const left = Type.atom("abc");
      const right = Type.string("abc");

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  describe("float type", () => {
    it("is matching another boxed float having the same value", () => {
      const left = Type.float(1.23);
      const right = Type.float(1.23);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed float having a different value", () => {
      const left = Type.float(1.23);
      const right = Type.float(2.34);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-float boxed type", () => {
      const left = Type.float(1.0);
      const right = Type.integer(1);

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  describe("integer type", () => {
    it("is matching another boxed integer having the same value", () => {
      const left = Type.integer(123);
      const right = Type.integer(123);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed integer having a different value", () => {
      const left = Type.integer(1);
      const right = Type.integer(2);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-integer boxed type", () => {
      const left = Type.integer(123);
      const right = Type.string("123");

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  describe("list type", () => {
    it("is matching another boxed list having the same items", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list([Type.integer(1), Type.integer(2)]);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed list having different items", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.list([Type.integer(1), Type.integer(3)]);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-list boxed type", () => {
      const left = Type.list([Type.integer(1), Type.integer(2)]);
      const right = Type.string("123");

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  describe("map type", () => {
    let data;

    beforeEach(() => {
      data = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
      ];
    });

    it("is matching another boxed map having the same items", () => {
      const left = Type.map(data);
      const right = Type.map(data);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is matching another boxed map which has all the same items as in the left map plus additional ones", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("c"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed map if any left map keys are missing in the right map ", () => {
      const data1 = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(2)],
        [Type.atom("c"), Type.integer(3)],
      ];

      const left = Type.map(data1);
      const right = Type.map(data);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed map if any left map value is different than corresponding value in the right map", () => {
      const left = Type.map(data);

      const data2 = [
        [Type.atom("a"), Type.integer(1)],
        [Type.atom("b"), Type.integer(3)],
      ];

      const right = Type.map(data2);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-map boxed type", () => {
      const left = Type.map(data);
      const right = Type.string("123");

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  it("match placeholder", () => {
    const left = Type.matchPlaceholder();
    const right = Type.integer(123);

    assert.isTrue(Interpreter.isMatched(left, right));
  });

  describe("tuple type", () => {
    it("is matching another boxed tuple having the same items", () => {
      const left = Type.tuple([Type.integer(1), Type.integer(2)]);
      const right = Type.tuple([Type.integer(1), Type.integer(2)]);

      assert.isTrue(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed tuple having different items", () => {
      const left = Type.tuple([Type.integer(1), Type.integer(2)]);
      const right = Type.tuple([Type.integer(1), Type.integer(3)]);

      assert.isFalse(Interpreter.isMatched(left, right));
    });

    it("is not matching another boxed value of a non-tuple boxed type", () => {
      const left = Type.tuple([Type.integer(1), Type.integer(2)]);
      const right = Type.string("123");

      assert.isFalse(Interpreter.isMatched(left, right));
    });
  });

  it("variable pattern", () => {
    const left = Type.variablePattern("abc");
    const right = Type.integer(123);

    assert.isTrue(Interpreter.isMatched(left, right));
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

describe("inspect()", () => {
  it("inspects boxed atom not being boolean or nil", () => {
    const result = Interpreter.inspect(Type.atom("abc"));
    assert.equal(result, ":abc");
  });

  it("inspects boxed atom being boolean", () => {
    const result = Interpreter.inspect(Type.boolean(true));
    assert.equal(result, "true");
  });

  it("inspects boxed atom being nil", () => {
    const result = Interpreter.inspect(Type.nil());
    assert.equal(result, "nil");
  });

  it("inspects boxed float", () => {
    const result = Interpreter.inspect(Type.float(123.45));
    assert.equal(result, "123.45");
  });

  it("inspects boxed integer", () => {
    const result = Interpreter.inspect(Type.integer(123));
    assert.equal(result, "123");
  });

  it("inspects boxed list", () => {
    const term = Type.list([Type.integer(123), Type.atom("abc")]);
    const result = Interpreter.inspect(term);

    assert.equal(result, "[123, :abc]");
  });

  it("inspects boxed tuple", () => {
    const term = Type.tuple([Type.integer(123), Type.atom("abc")]);
    const result = Interpreter.inspect(term);

    assert.equal(result, "{123, :abc}");
  });

  it("inspects other boxed types", () => {
    const segment = Type.bitstringSegment(Type.integer(170), {type: "integer"});
    const term = Type.bitstring([segment]);
    const result = Interpreter.inspect(term);

    assert.equal(
      result,
      '{"type":"bitstring","bits":{"0":1,"1":0,"2":1,"3":0,"4":1,"5":0,"6":1,"7":0}}'
    );
  });

  // TODO: test other boxed types
});

describe("matchOperator()", () => {
  let vars;

  beforeEach(() => {
    vars = {a: Type.integer(9)};
  });

  it("raises MatchError if the arguments don't match", () => {
    assertError(
      () => Interpreter.matchOperator(Type.integer(1), Type.integer(2), vars),
      "MatchError",
      "no match of right hand side value: 2"
    );
  });

  it("matches on atom type", () => {
    const result = Interpreter.matchOperator(
      Type.atom("abc"),
      Type.atom("abc"),
      vars
    );

    assert.deepStrictEqual(result, Type.atom("abc"));
    assert.deepStrictEqual(vars, {a: Type.integer(9)});
  });

  it("matches on float type", () => {
    const result = Interpreter.matchOperator(
      Type.float(2.0),
      Type.float(2.0),
      vars
    );

    assert.deepStrictEqual(result, Type.float(2.0));
    assert.deepStrictEqual(vars, {a: Type.integer(9)});
  });

  it("matches on integer type", () => {
    const result = Interpreter.matchOperator(
      Type.integer(2),
      Type.integer(2),
      vars
    );

    assert.deepStrictEqual(result, Type.integer(2));
    assert.deepStrictEqual(vars, {a: Type.integer(9)});
  });

  it("matches on list type", () => {
    const left = Type.list([
      Type.variablePattern("b"),
      Type.integer(2),
      Type.variablePattern("a"),
    ]);

    const right = Type.list([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);

    const result = Interpreter.matchOperator(left, right, vars);

    assert.deepStrictEqual(result, right);
    assert.deepStrictEqual(vars, {a: Type.integer(3), b: Type.integer(1)});
  });

  it("matches on map type", () => {
    const data1 = [
      [Type.atom("a"), Type.variablePattern("a")],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.variablePattern("c")],
    ];

    const left = Type.map(data1);

    const data2 = [
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ];

    const right = Type.map(data2);

    const result = Interpreter.matchOperator(left, right, vars);

    assert.deepStrictEqual(result, right);
    assert.deepStrictEqual(vars, {a: Type.integer(1), c: Type.integer(3)});
  });

  it("matches on match placeholder", () => {
    const result = Interpreter.matchOperator(
      Type.matchPlaceholder(),
      Type.integer(2),
      vars
    );

    assert.deepStrictEqual(result, Type.integer(2));
    assert.deepStrictEqual(vars, {a: Type.integer(9)});
  });

  it("matches on tuple type", () => {
    const left = Type.tuple([
      Type.variablePattern("b"),
      Type.integer(2),
      Type.variablePattern("a"),
    ]);

    const right = Type.tuple([
      Type.integer(1),
      Type.integer(2),
      Type.integer(3),
    ]);

    const result = Interpreter.matchOperator(left, right, vars);

    assert.deepStrictEqual(result, right);
    assert.deepStrictEqual(vars, {a: Type.integer(3), b: Type.integer(1)});
  });

  it("matches on variable pattern", () => {
    const result = Interpreter.matchOperator(
      Type.variablePattern("a"),
      Type.integer(2),
      vars
    );

    assert.deepStrictEqual(result, Type.integer(2));
    assert.deepStrictEqual(vars, {a: Type.integer(2)});
  });
});

it("raiseCaseClauseError()", () => {
  assertError(
    () => Interpreter.raiseCaseClauseError("abc"),
    "CaseClauseError",
    "abc"
  );
});

it("raiseCondClauseError()", () => {
  const expectedMessage = "no cond clause evaluated to a truthy value";
  assertError(
    () => Interpreter.raiseCondClauseError(),
    "CondClauseError",
    expectedMessage
  );
});

it("raiseFunctionClauseError()", () => {
  assertError(
    () => Interpreter.raiseFunctionClauseError("abc"),
    "FunctionClauseError",
    "abc"
  );
});

describe("tail()", () => {
  it("returns the tail of a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Interpreter.tail(list);
    const expected = Type.list([Type.integer(2), Type.integer(3)]);

    assert.deepStrictEqual(result, expected);
  });
});
