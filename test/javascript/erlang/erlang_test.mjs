"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedFalse,
  assertBoxedTrue,
  linkModules,
  unlinkModules,
} from "../../../assets/js/test_support.mjs";

import Erlang from "../../../assets/js/erlang/erlang.mjs";
import HologramInterpreterError from "../../../assets/js/errors/interpreter_error.mjs";
import Interpreter from "../../../assets/js/interpreter.mjs";
import Type from "../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/erlang_test.exs
// Always update both together.

describe("*/2", () => {
  it("multiplies integer by integer", () => {
    const left = Type.integer(2);
    const right = Type.integer(3);

    const result = Erlang["*/2"](left, right);
    const expected = Type.integer(6);

    assert.deepStrictEqual(result, expected);
  });

  it("multiplies integer by float", () => {
    const left = Type.integer(2);
    const right = Type.float(3.0);

    const result = Erlang["*/2"](left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("multiplies float by integer", () => {
    const left = Type.float(2.0);
    const right = Type.integer(3);

    const result = Erlang["*/2"](left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("miltiplies float by float", () => {
    const left = Type.float(2.0);
    const right = Type.float(3.0);

    const result = Erlang["*/2"](left, right);
    const expected = Type.float(6.0);

    assert.deepStrictEqual(result, expected);
  });

  it("raises ArgumentError if the first argument is not a number", () => {
    assertBoxedError(
      () => Erlang["*/2"](Type.atom("abc"), Type.integer(123)),
      "ArgumentError",
      "bad argument in arithmetic expression: :abc * 123",
    );
  });

  it("raises ArgumentError if the second argument is not a number", () => {
    assertBoxedError(
      () => Erlang["*/2"](Type.integer(123), Type.atom("abc")),
      "ArgumentError",
      "bad argument in arithmetic expression: 123 * :abc",
    );
  });
});

describe("+/2", () => {
  it("adds integer and integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);

    const result = Erlang["+/2"](left, right);
    const expected = Type.integer(3);

    assert.deepStrictEqual(result, expected);
  });

  it("adds integer and float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);

    const result = Erlang["+/2"](left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);

    const result = Erlang["+/2"](left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });

  it("adds float and float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);

    const result = Erlang["+/2"](left, right);
    const expected = Type.float(3.0);

    assert.deepStrictEqual(result, expected);
  });
});

describe("-/2", () => {
  it("subtracts integer and integer", () => {
    const left = Type.integer(3);
    const right = Type.integer(1);

    const result = Erlang["-/2"](left, right);
    const expected = Type.integer(2);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts integer and float", () => {
    const left = Type.integer(3);
    const right = Type.float(1.0);

    const result = Erlang["-/2"](left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts float and integer", () => {
    const left = Type.float(3.0);
    const right = Type.integer(1);

    const result = Erlang["-/2"](left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });

  it("subtracts float and float", () => {
    const left = Type.float(3.0);
    const right = Type.float(1.0);

    const result = Erlang["-/2"](left, right);
    const expected = Type.float(2.0);

    assert.deepStrictEqual(result, expected);
  });
});

describe("/=/2", () => {
  // non-number == non-number
  it("returns boxed false for a boxed non-number equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.boolean(true);
    const result = Erlang["/=/2"](left, right);

    assertBoxedFalse(result);
  });

  // non-number != non-number
  it("returns boxed true for a boxed non-number not equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.string("abc");
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // integer == integer
  it("returns boxed false for a boxed integer equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang["/=/2"](left, right);

    assertBoxedFalse(result);
  });

  // integer != integer
  it("returns boxed true for a boxed integer not equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // integer == float
  it("returns boxed false for a boxed integer equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(1.0);
    const result = Erlang["/=/2"](left, right);

    assertBoxedFalse(result);
  });

  // integer != float
  it("returns boxed true for a boxed integer not equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // integer != non-number
  it("returns boxed true when a boxed integer is compared to a boxed value of non-number type", () => {
    const left = Type.integer(1);
    const right = Type.string("1");
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // float == float
  it("returns boxed false for a boxed float equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(1.0);
    const result = Erlang["/=/2"](left, right);

    assertBoxedFalse(result);
  });

  // float != float
  it("returns boxed true for a boxed float not equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // float == integer
  it("returns boxed false for a boxed float equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(1);
    const result = Erlang["/=/2"](left, right);

    assertBoxedFalse(result);
  });

  // float != integer
  it("returns boxed true for a boxed float not equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });

  // float != non-number
  it("returns boxed true when a boxed float is compared to a boxed value of non-number type", () => {
    const left = Type.float(1.0);
    const right = Type.string("1.0");
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });
});

describe("</2", () => {
  it("returns boxed true when left float argument is smaller than right float argument", () => {
    const left = Type.float(3.2);
    const right = Type.float(5.6);
    const result = Erlang["</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left float argument is smaller than right integer argument", () => {
    const left = Type.float(3.2);
    const right = Type.integer(5);
    const result = Erlang["</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left integer argument is smaller than right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(5.6);
    const result = Erlang["</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left integer argument is smaller than right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(5);
    const result = Erlang["</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed false when left float argument is equal to right float argument", () => {
    const left = Type.float(3.0);
    const right = Type.float(3.0);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is equal to right integer argument", () => {
    const left = Type.float(3.0);
    const right = Type.integer(3);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is equal to right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(3.0);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is equal to right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(3);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is greater than right float argument", () => {
    const left = Type.float(5.6);
    const right = Type.float(3.2);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is greater than right integer argument", () => {
    const left = Type.float(5.6);
    const right = Type.integer(3);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is greater than right float argument", () => {
    const left = Type.integer(5);
    const right = Type.float(3.2);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is greater than right integer argument", () => {
    const left = Type.integer(5);
    const right = Type.integer(3);
    const result = Erlang["</2"](left, right);

    assertBoxedFalse(result);
  });

  it("throws a not yet implemented error for non-integer and non-float left argument", () => {
    const left = Type.string("abc");
    const right = Type.integer(2);

    const expectedMessage =
      ':erlang.</2 currently supports only floats and integers, left = "abc", right = 2';

    assert.throw(
      () => Erlang["</2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error for non-integer and non-float right argument", () => {
    const left = Type.integer(2);
    const right = Type.string("abc");

    const expectedMessage =
      ':erlang.</2 currently supports only floats and integers, left = 2, right = "abc"';

    assert.throw(
      () => Erlang["</2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });
});

describe("=:=/2", () => {
  it("proxies to Interpreter.isStrictlyEqual/2 and casts the result to boxed boolean", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang["=:=/2"](left, right);
    const expected = Type.boolean(Interpreter.isStrictlyEqual(left, right));

    assert.deepStrictEqual(result, expected);
  });
});

describe("==/2", () => {
  // non-number == non-number
  it("returns boxed true for a boxed non-number equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.boolean(true);
    const result = Erlang["==/2"](left, right);

    assertBoxedTrue(result);
  });

  // non-number != non-number
  it("returns boxed false for a boxed non-number not equal to another boxed non-number", () => {
    const left = Type.boolean(true);
    const right = Type.string("abc");
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // integer == integer
  it("returns boxed true for a boxed integer equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(1);
    const result = Erlang["==/2"](left, right);

    assertBoxedTrue(result);
  });

  // integer != integer
  it("returns boxed false for a boxed integer not equal to another boxed integer", () => {
    const left = Type.integer(1);
    const right = Type.integer(2);
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // integer == float
  it("returns boxed true for a boxed integer equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(1.0);
    const result = Erlang["==/2"](left, right);

    assertBoxedTrue(result);
  });

  // integer != float
  it("returns boxed false for a boxed integer not equal to a boxed float", () => {
    const left = Type.integer(1);
    const right = Type.float(2.0);
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // integer != non-number
  it("returns boxed false when a boxed integer is compared to a boxed value of non-number type", () => {
    const left = Type.integer(1);
    const right = Type.string("1");
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // float == float
  it("returns boxed true for a boxed float equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(1.0);
    const result = Erlang["==/2"](left, right);

    assertBoxedTrue(result);
  });

  // float != float
  it("returns boxed false for a boxed float not equal to another boxed float", () => {
    const left = Type.float(1.0);
    const right = Type.float(2.0);
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // float == integer
  it("returns boxed true for a boxed float equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(1);
    const result = Erlang["==/2"](left, right);

    assertBoxedTrue(result);
  });

  // float != integer
  it("returns boxed false for a boxed float not equal to a boxed integer", () => {
    const left = Type.float(1.0);
    const right = Type.integer(2);
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });

  // float != non-number
  it("returns boxed false when a boxed float is compared to a boxed value of non-number type", () => {
    const left = Type.float(1.0);
    const right = Type.string("1.0");
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });
});

describe(">/2", () => {
  it("returns boxed true when left float argument is greater than right float argument", () => {
    const left = Type.float(5.6);
    const right = Type.float(3.2);
    const result = Erlang[">/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left float argument is greater than right integer argument", () => {
    const left = Type.float(5.6);
    const right = Type.integer(3);
    const result = Erlang[">/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left integer argument is greater than right float argument", () => {
    const left = Type.integer(5);
    const right = Type.float(3.2);
    const result = Erlang[">/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed true when left integer argument is greater than right integer argument", () => {
    const left = Type.integer(5);
    const right = Type.integer(3);
    const result = Erlang[">/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns boxed false when left float argument is equal to right float argument", () => {
    const left = Type.float(3.0);
    const right = Type.float(3.0);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is equal to right integer argument", () => {
    const left = Type.float(3.0);
    const right = Type.integer(3);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is equal to right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(3.0);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is equal to right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(3);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is smaller than right float argument", () => {
    const left = Type.float(3.2);
    const right = Type.float(5.6);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left float argument is smaller than right integer argument", () => {
    const left = Type.float(3.2);
    const right = Type.integer(5);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is smaller than right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(5.6);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns boxed false when left integer argument is smaller than right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(5);
    const result = Erlang[">/2"](left, right);

    assertBoxedFalse(result);
  });

  it("throws a not yet implemented error for non-integer and non-float left argument", () => {
    const left = Type.string("abc");
    const right = Type.integer(2);

    const expectedMessage =
      ':erlang.>/2 currently supports only floats and integers, left = "abc", right = 2';

    assert.throw(
      () => Erlang[">/2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error for non-integer and non-float right argument", () => {
    const left = Type.integer(2);
    const right = Type.string("abc");

    const expectedMessage =
      ':erlang.>/2 currently supports only floats and integers, left = 2, right = "abc"';

    assert.throw(
      () => Erlang[">/2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });
});

it("error/1", () => {
  const reason = Type.errorStruct("MyError", "my message");

  assertBoxedError(() => Erlang["error/1"](reason), "MyError", "my message");
});

it("error/2", () => {
  const reason = Type.errorStruct("MyError", "my message");
  const args = Type.list([Type.integer(1, Type.integer(2))]);

  assertBoxedError(
    () => Erlang["error/2"](reason, args),
    "MyError",
    "my message",
  );
});

describe("hd/1", () => {
  it("returns the first item in a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2), Type.integer(3)]);
    const result = Erlang["hd/1"](list);

    assert.deepStrictEqual(result, Type.integer(1));
  });

  it("raises ArgumentError if the argument is an empty boxed list", () => {
    assertBoxedError(
      () => Erlang["hd/1"](Type.list([])),
      "ArgumentError",
      "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
    );
  });

  it("raises ArgumentError if the argument is not a boxed list", () => {
    assertBoxedError(
      () => Erlang["hd/1"](Type.integer(123)),
      "ArgumentError",
      "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
    );
  });
});

describe("is_atom/1", () => {
  it("proxies to Type.isAtom() and casts the result to boxed boolean", () => {
    const term = Type.atom("abc");
    const result = Erlang["is_atom/1"](term);
    const expected = Type.boolean(Type.isAtom(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_bitstring/1", () => {
  it("returns true if the term is a bitstring", () => {
    const term = Type.bitstring("abc");
    assertBoxedTrue(Erlang["is_bitstring/1"](term));
  });

  it("returns false if the term is not a bitstring", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_bitstring/1"](term));
  });
});

describe("is_float/1", () => {
  it("proxies to Type.isFloat() and casts the result to boxed boolean", () => {
    const term = Type.float(1.23);
    const result = Erlang["is_float/1"](term);
    const expected = Type.boolean(Type.isFloat(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_function/1", () => {
  it("returns true if the term is an anonymous function", () => {
    const term = Type.anonymousFunction(3, ["dummy_clause"], {});
    assertBoxedTrue(Erlang["is_function/1"](term));
  });

  it("returns false if the term is not an anonymous function", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_function/1"](term));
  });
});

describe("is_integer/1", () => {
  it("proxies to Type.isInteger() and casts the result to boxed boolean", () => {
    const term = Type.integer(123);
    const result = Erlang["is_integer/1"](term);
    const expected = Type.boolean(Type.isInteger(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_list/1", () => {
  it("proxies to Type.isList() and casts the result to boxed boolean", () => {
    const term = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Erlang["is_list/1"](term);
    const expected = Type.boolean(Type.isList(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_map/1", () => {
  it("returns true if the term is a map", () => {
    const term = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    assertBoxedTrue(Erlang["is_map/1"](term));
  });

  it("returns false if the term is not a map", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_map/1"](term));
  });
});

describe("is_number/1", () => {
  it("proxies to Type.isNumber() and casts the result to boxed boolean", () => {
    const term = Type.integer(123);
    const result = Erlang["is_number/1"](term);
    const expected = Type.boolean(Type.isNumber(term));

    assert.deepStrictEqual(result, expected);
  });
});

describe("is_tuple/1", () => {
  it("returns true if the term is a tuple", () => {
    const term = Type.tuple([Type.integer(1), Type.integer(2)]);
    assertBoxedTrue(Erlang["is_tuple/1"](term));
  });

  it("returns false if the term is not a tuple", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_tuple/1"](term));
  });
});

describe("length/1", () => {
  it("returns the number of items in a boxed list", () => {
    const list = Type.list([Type.integer(1), Type.integer(2)]);
    const result = Erlang["length/1"](list);

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("raises ArgumentError if the argument is not a boxed list", () => {
    assertBoxedError(
      () => Erlang["length/1"](Type.integer(123)),
      "ArgumentError",
      "errors were found at the given arguments:\n\n* 1st argument: not a list",
    );
  });
});

describe("map_size/1", () => {
  it("returns the number of items in a boxed map", () => {
    const map = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const result = Erlang["map_size/1"](map);

    assert.deepStrictEqual(result, Type.integer(2));
  });

  it("raises BadMapError if the argument is not a boxed map", () => {
    assertBoxedError(
      () => Erlang["map_size/1"](Type.atom("abc")),
      "BadMapError",
      "expected a map, got: :abc",
    );
  });
});

describe("tl/1", () => {
  describe("proper list", () => {
    it("1 item", () => {
      const list = Type.list([Type.integer(1)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.list([]);

      assert.deepStrictEqual(result, expected);
    });

    it("2 items", () => {
      const list = Type.list([Type.integer(1), Type.integer(2)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.list([Type.integer(2)]);

      assert.deepStrictEqual(result, expected);
    });

    it("3 items", () => {
      const list = Type.list([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Erlang["tl/1"](list);
      const expected = Type.list([Type.integer(2), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("improper list", () => {
    it("2 items", () => {
      const list = Type.improperList([Type.integer(1), Type.integer(2)]);
      const result = Erlang["tl/1"](list);
      const expected = Type.integer(2);

      assert.deepStrictEqual(result, expected);
    });

    it("3 items", () => {
      const list = Type.improperList([
        Type.integer(1),
        Type.integer(2),
        Type.integer(3),
      ]);

      const result = Erlang["tl/1"](list);
      const expected = Type.improperList([Type.integer(2), Type.integer(3)]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("errors", () => {
    it("raises ArgumentError if the argument is an empty boxed list", () => {
      assertBoxedError(
        () => Erlang["tl/1"](Type.list([])),
        "ArgumentError",
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
      );
    });

    it("raises ArgumentError if the argument is not a boxed list", () => {
      assertBoxedError(
        () => Erlang["tl/1"](Type.integer(123)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
      );
    });
  });
});
