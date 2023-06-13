"use strict";

import {assert} from "../../assets/js/test_support.mjs";
import Erlang from "../../assets/js/erlang/erlang.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import Type from "../../assets/js/type.mjs";

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
          guard: (vars) => Erlang.$61$61(vars.x, Type.integer(1n)),
          body: (vars) => {
            return Type.atom("expr_1");
          },
        },
        {
          params: [Type.variablePattern("y")],
          guard: (vars) => Erlang.$61$61(vars.y, Type.integer(2n)),
          body: (vars) => {
            return Type.atom("expr_2");
          },
        },
        {
          params: [Type.variablePattern("z")],
          guard: (vars) => Erlang.$61$61(vars.z, Type.integer(3n)),
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
          guard: (vars) => Erlang.$61$61(vars.x, Type.integer(1n)),
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

  it("raise FunctionClauseError error if none of the clauses is matched", () => {
    assert.throw(
      () => {
        Interpreter.callAnonymousFunction(anonFun, [Type.integer(3)]);
      },
      Error,
      "(FunctionClauseError) no function clause matching in anonymous fn/1"
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
  it("inspects boxed atom", () => {
    const result = Interpreter.inspect(Type.atom("abc"));
    assert.equal(result, ":abc");
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
    assert.throw(
      () => {
        Interpreter.matchOperator(Type.integer(1), Type.integer(2), vars);
      },
      Error,
      "(MatchError) no match of right hand side value: 2"
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

describe("raiseError()", () => {
  it("throws an error with the given message", () => {
    assert.throw(
      () => {
        Interpreter.raiseError("MyType", "my message");
      },
      Error,
      "(MyType) my message"
    );
  });
});

describe("raiseNotYetImplementedError()", () => {
  it("throws a Hologram.NotYetImplemented error with the given message", () => {
    assert.throw(
      () => {
        Interpreter.raiseNotYetImplementedError("my message");
      },
      Error,
      "(Hologram.NotYetImplementedError) my message"
    );
  });
});

describe("tail()", () => {
  it("returns the tail of a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Interpreter.tail(list);
    const expected = Type.list([Type.integer(2), Type.integer(3)]);

    assert.deepStrictEqual(result, expected);
  });
});
