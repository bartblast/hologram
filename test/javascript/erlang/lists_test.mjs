"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  contextFixture,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Erlang_Lists from "../../../assets/js/erlang/lists.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const emptyList = Type.list();

const improperList = Type.improperList([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

const properList = Type.list([
  Type.integer(1),
  Type.integer(2),
  Type.integer(3),
]);

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/lists_test.exs
// Always update both together.

describe("Erlang_Lists", () => {
  describe("flatten/1", () => {
    const flatten = Erlang_Lists["flatten/1"];

    it("works with empty list", () => {
      const result = flatten(emptyList);
      assert.deepStrictEqual(result, emptyList);
    });

    it("works with non-nested list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = flatten(list);

      assert.deepStrictEqual(result, list);
    });

    it("works with nested list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.list([
          Type.integer(2),
          Type.list([Type.integer(3), Type.integer(4), Type.integer(5)]),
          Type.integer(6),
        ]),
        Type.integer(7),
      ]);

      const result = flatten(list);

      const expected = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
        Type.integer(4),
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      assertBoxedError(
        () => flatten(Type.atom("abc")),
        "FunctionClauseError",
        "no function clause matching in :lists.flatten/1",
      );
    });

    it("raises FunctionClauseError if the argument (or any nested item) is an improper list", () => {
      assertBoxedError(
        () =>
          flatten(
            Type.list([
              Type.integer(1),
              Type.integer(2),
              Type.improperList([
                Type.integer(3),
                Type.integer(4),
                Type.integer(5),
              ]),
              Type.integer(6),
              Type.integer(7),
            ]),
          ),
        "FunctionClauseError",
        "no function clause matching in :lists.do_flatten/2",
      );
    });
  });

  describe("foldl/3", () => {
    const foldl = Erlang_Lists["foldl/3"];

    const fun = Type.anonymousFunction(
      2,
      [
        {
          params: (_context) => [
            Type.variablePattern("elem"),
            Type.variablePattern("acc"),
          ],
          guards: [],
          body: (context) => {
            return Erlang["+/2"](context.vars.acc, context.vars.elem);
          },
        },
      ],
      contextFixture(),
    );

    const acc = Type.integer(0);

    it("reduces empty list", () => {
      const result = foldl(fun, acc, emptyList);
      assert.deepStrictEqual(result, acc);
    });

    it("reduces non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = foldl(fun, acc, list);

      assert.deepStrictEqual(result, Type.integer(6));
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      assertBoxedError(
        () => foldl(Type.atom("abc"), acc, emptyList),
        "FunctionClauseError",
        "no function clause matching in :lists.foldl/3",
      );
    });

    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 2", () => {
      const fun = Type.anonymousFunction(
        1,
        [
          {
            params: (_context) => [Type.variablePattern("x")],
            guards: [],
            body: (context) => {
              return context.vars.x;
            },
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => foldl(fun, acc, emptyList),
        "FunctionClauseError",
        "no function clause matching in :lists.foldl/3",
      );
    });

    it("raises CaseClauseError if the third argument is not a list", () => {
      assertBoxedError(
        () => foldl(fun, acc, Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    it("raises FunctionClauseError if the third argument is an improper list", () => {
      assertBoxedError(
        () =>
          foldl(
            fun,
            acc,
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "FunctionClauseError",
        "no function clause matching in :lists.foldl_1/3",
      );
    });
  });

  describe("keyfind/3", () => {
    const keyfind = Erlang_Lists["keyfind/3"];

    it("returns the tuple that contains the given value at the given one-based index", () => {
      const tuple = Type.tuple([
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      const tuples = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.atom("abc"),
        tuple,
      ]);

      const result = keyfind(Type.integer(7), Type.integer(3), tuples);

      assert.deepStrictEqual(result, tuple);
    });

    it("returns false if there is no tuple that fulfills the given conditions", () => {
      const result = keyfind(
        Type.integer(7),
        Type.integer(3),
        Type.list([Type.atom("abc")]),
      );

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.atom("xyz"), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.integer(0), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is not a list", () => {
      assertBoxedError(
        () => keyfind(Type.atom("abc"), Type.integer(1), Type.atom("xyz")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is an improper list", () => {
      assertBoxedError(
        () =>
          keyfind(
            Type.integer(7),
            Type.integer(4),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    });
  });

  describe("keymember/3", () => {
    const keymember = Erlang_Lists["keymember/3"];

    it("returns true if there is a tuple that fulfills the given conditions", () => {
      const tuple = Type.tuple([
        Type.integer(5),
        Type.integer(6),
        Type.integer(7),
      ]);

      const tuples = Type.list([
        Type.tuple([Type.integer(1), Type.integer(2)]),
        Type.atom("abc"),
        tuple,
      ]);

      const result = keymember(Type.integer(7), Type.integer(3), tuples);

      assertBoxedTrue(result);
    });

    it("returns false if there is no tuple that fulfills the given conditions", () => {
      const result = keymember(
        Type.integer(7),
        Type.integer(3),
        Type.list([Type.atom("abc")]),
      );

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument (index) is not an integer", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.atom("xyz"), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    });

    it("raises ArgumentError if the second argument (index) is smaller than 1", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.integer(0), Type.list()),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is not a list", () => {
      assertBoxedError(
        () => keymember(Type.atom("abc"), Type.integer(1), Type.atom("xyz")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    });

    it("raises ArgumentError if the third argument (tuples) is an improper list", () => {
      assertBoxedError(
        () =>
          keymember(
            Type.integer(7),
            Type.integer(4),
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    });
  });

  describe("map/2", () => {
    const fun = Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("elem")],
          guards: [],
          body: (context) => {
            return Erlang["*/2"](context.vars.elem, Type.integer(10));
          },
        },
      ],
      contextFixture(),
    );

    const map = Erlang_Lists["map/2"];

    it("maps empty list", () => {
      const result = map(fun, emptyList);
      assert.deepStrictEqual(result, emptyList);
    });

    it("maps non-empty list", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);
      const result = map(fun, list);

      const expected = Type.list([
        Type.integer(10),
        Type.integer(20),
        Type.integer(30),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the first argument is not an anonymous function", () => {
      assertBoxedError(
        () => map(Type.atom("abc"), emptyList),
        "FunctionClauseError",
        "no function clause matching in :lists.map/2",
      );
    });

    it("raises FunctionClauseError if the first argument is an anonymous function with arity different than 1", () => {
      const fun = Type.anonymousFunction(
        2,
        [
          {
            params: (_context) => [
              Type.variablePattern("x"),
              Type.variablePattern("y"),
            ],
            guards: [],
            body: (context) => {
              return Erlang["+/2"](context.vars.x, context.vars.y);
            },
          },
        ],
        contextFixture(),
      );

      assertBoxedError(
        () => map(fun, emptyList),
        "FunctionClauseError",
        "no function clause matching in :lists.map/2",
      );
    });

    it("raises CaseClauseError if the second argument is not a list", () => {
      assertBoxedError(
        () => map(fun, Type.atom("abc")),
        "CaseClauseError",
        "no case clause matching: :abc",
      );
    });

    it("raises FunctionClauseError if the second argument is an improper list", () => {
      assertBoxedError(
        () =>
          map(
            fun,
            Type.improperList([
              Type.integer(1),
              Type.integer(2),
              Type.integer(3),
            ]),
          ),
        "FunctionClauseError",
        "no function clause matching in :lists.map_1/2",
      );
    });
  });

  describe("member/2", () => {
    const member = Erlang_Lists["member/2"];

    it("is a member of a proper list", () => {
      const result = member(Type.integer(2), properList);
      assertBoxedTrue(result);
    });

    it("is a non-last member of an improper list", () => {
      const result = member(Type.integer(2), improperList);
      assertBoxedTrue(result);
    });

    it("is the last member of an improper list", () => {
      assertBoxedError(
        () => member(Type.integer(3), improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });

    it("is not a member of a proper list", () => {
      const result = member(Type.integer(4), properList);
      assertBoxedFalse(result);
    });

    it("is not a member of an improper list", () => {
      assertBoxedError(
        () => member(Type.integer(4), improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    });

    it("uses strict equality", () => {
      const list = Type.list([
        Type.integer(1),
        Type.float(2.0),
        Type.integer(3),
      ]);
      const result = member(Type.integer(2), list);

      assertBoxedFalse(result);
    });

    it("raises ArgumentError if the second argument is not a list", () => {
      assertBoxedError(
        () => member(Type.integer(2), Type.atom("abc")),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    });
  });

  describe("reverse/1", () => {
    const reverse = Erlang_Lists["reverse/1"];

    it("returns a list with the elements in the argument in reverse order", () => {
      const result = reverse(properList);

      const expected = Type.list([
        Type.integer(3),
        Type.integer(2),
        Type.integer(1),
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      assertBoxedError(
        () => reverse(Type.atom("abc")),
        "FunctionClauseError",
        "no function clause matching in :lists.reverse/1",
      );
    });

    it("raises ArgumentError if the argument is not a proper list", () => {
      assertBoxedError(
        () => reverse(improperList),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("reverse/2", () => {
    const reverse = Erlang_Lists["reverse/2"];

    const integer1 = Type.integer(1);
    const integer2 = Type.integer(2);
    const integer3 = Type.integer(3);
    const integer4 = Type.integer(4);
    const integer5 = Type.integer(5);

    const list12 = Type.list([integer1, integer2]);
    const list34 = Type.list([integer3, integer4]);

    const improperList12 = Type.improperList([integer1, integer2]);
    const improperList34 = Type.improperList([integer3, integer4]);

    describe("1st arg = [1, 2]", () => {
      it("2nd arg = [3, 4]", () => {
        const expected = Type.list([integer2, integer1, integer3, integer4]);
        assert.deepStrictEqual(reverse(list12, list34), expected);
      });

      it("2nd arg = [3 | 4]", () => {
        const expected = Type.improperList([
          integer2,
          integer1,
          integer3,
          integer4,
        ]);
        assert.deepStrictEqual(reverse(list12, improperList34), expected);
      });

      it("2nd arg = []", () => {
        const expected = Type.list([integer2, integer1]);
        assert.deepStrictEqual(reverse(list12, emptyList), expected);
      });

      it("2nd arg = 5", () => {
        const expected = Type.improperList([integer2, integer1, integer5]);
        assert.deepStrictEqual(reverse(list12, integer5), expected);
      });
    });

    it("1st arg is an improper list", () => {
      assertBoxedError(
        () => reverse(improperList12, list34),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    });

    describe("1st arg = []", () => {
      it("2nd arg = [3, 4]", () => {
        assert.deepStrictEqual(reverse(emptyList, list34), list34);
      });

      it("2nd arg = [3 | 4]", () => {
        assert.deepStrictEqual(
          reverse(emptyList, improperList34),
          improperList34,
        );
      });

      it("2nd arg = []", () => {
        assert.deepStrictEqual(reverse(emptyList, emptyList), emptyList);
      });

      it("2nd arg = 5", () => {
        assert.deepStrictEqual(reverse(emptyList, integer5), integer5);
      });
    });

    it("1st arg is not a list", () => {
      assertBoxedError(
        () => reverse(integer5, list34),
        "ArgumentError",
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    });
  });

  describe("sort/1", () => {
    const sort = Erlang_Lists["sort/1"];

    it("sorts items in the list", () => {
      const list = Type.list([
        Type.atom("a"),
        Type.integer(4),
        Type.float(3.0),
        Type.atom("b"),
        Type.integer(1),
        Type.float(2.0),
      ]);

      assert.deepStrictEqual(
        sort(list),
        Type.list([
          Type.integer(1),
          Type.float(2.0),
          Type.float(3.0),
          Type.integer(4),
          Type.atom("a"),
          Type.atom("b"),
        ]),
      );
    });

    it("raises FunctionClauseError if the argument is not a list", () => {
      assertBoxedError(
        () => sort(Type.atom("abc")),
        "FunctionClauseError",
        "no function clause matching in :lists.sort/1",
      );
    });

    it("raises FunctionClauseError if the argument is an improper list", () => {
      assertBoxedError(
        () => sort(improperList),
        "FunctionClauseError",
        "no function clause matching in :lists.split_1/5",
      );
    });
  });
});
