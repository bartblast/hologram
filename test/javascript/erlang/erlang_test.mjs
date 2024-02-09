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

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => Erlang["*/2"](Type.atom("abc"), Type.integer(123)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => Erlang["*/2"](Type.integer(123), Type.atom("abc")),
      "ArithmeticError",
      "bad argument in arithmetic expression",
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

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => Erlang["+/2"](Type.atom("abc"), Type.integer(123)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => Erlang["+/2"](Type.integer(123), Type.atom("abc")),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
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

  it("raises ArithmeticError if the first argument is not a number", () => {
    assertBoxedError(
      () => Erlang["-/2"](Type.atom("abc"), Type.integer(123)),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
  });

  it("raises ArithmeticError if the second argument is not a number", () => {
    assertBoxedError(
      () => Erlang["-/2"](Type.integer(123), Type.atom("abc")),
      "ArithmeticError",
      "bad argument in arithmetic expression",
    );
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
    const right = Type.bitstring("abc");
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
    const right = Type.bitstring("1");
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
    const right = Type.bitstring("1.0");
    const result = Erlang["/=/2"](left, right);

    assertBoxedTrue(result);
  });
});

describe("</2", () => {
  it("left == right", () => {
    const result = Erlang["</2"](Type.integer(1), Type.integer(1));
    assertBoxedFalse(result);
  });

  it("left < right", () => {
    const result = Erlang["</2"](Type.integer(1), Type.integer(2));
    assertBoxedTrue(result);
  });

  it("left > right", () => {
    const result = Erlang["</2"](Type.integer(2), Type.integer(1));
    assertBoxedFalse(result);
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

describe("=</2", () => {
  it("returns true when left float argument is smaller than right float argument", () => {
    const left = Type.float(3.2);
    const right = Type.float(5.6);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is smaller than right integer argument", () => {
    const left = Type.float(3.2);
    const right = Type.integer(5);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is smaller than right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(5.6);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is smaller than right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(5);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is equal to right float argument", () => {
    const left = Type.float(3.0);
    const right = Type.float(3.0);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is equal to right integer argument", () => {
    const left = Type.float(3.0);
    const right = Type.integer(3);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is equal to right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(3.0);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is equal to right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(3);
    const result = Erlang["=</2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns false when left float argument is greater than right float argument", () => {
    const left = Type.float(5.6);
    const right = Type.float(3.2);
    const result = Erlang["=</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left float argument is greater than right integer argument", () => {
    const left = Type.float(5.6);
    const right = Type.integer(3);
    const result = Erlang["=</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left integer argument is greater than right float argument", () => {
    const left = Type.integer(5);
    const right = Type.float(3.2);
    const result = Erlang["=</2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left integer argument is greater than right integer argument", () => {
    const left = Type.integer(5);
    const right = Type.integer(3);
    const result = Erlang["=</2"](left, right);

    assertBoxedFalse(result);
  });

  it("throws a not yet implemented error for non-integer and non-float left argument", () => {
    const left = Type.bitstring("abc");
    const right = Type.integer(2);

    const expectedMessage =
      'Structural comparison currently supports only floats and integers, got: "abc"';

    assert.throw(
      () => Erlang["=</2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error for non-integer and non-float right argument", () => {
    const left = Type.integer(2);
    const right = Type.bitstring("abc");

    const expectedMessage =
      'Structural comparison currently supports only floats and integers, got: "abc"';

    assert.throw(
      () => Erlang["=</2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
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
    const right = Type.bitstring("abc");
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
    const right = Type.bitstring("1");
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
    const right = Type.bitstring("1.0");
    const result = Erlang["==/2"](left, right);

    assertBoxedFalse(result);
  });
});

describe(">/2", () => {
  it("left == right", () => {
    const result = Erlang[">/2"](Type.integer(1), Type.integer(1));
    assertBoxedFalse(result);
  });

  it("left < right", () => {
    const result = Erlang[">/2"](Type.integer(1), Type.integer(2));
    assertBoxedFalse(result);
  });

  it("left > right", () => {
    const result = Erlang[">/2"](Type.integer(2), Type.integer(1));
    assertBoxedTrue(result);
  });
});

describe(">=/2", () => {
  it("returns true when left float argument is greater than right float argument", () => {
    const left = Type.float(5.6);
    const right = Type.float(3.2);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is greater than right integer argument", () => {
    const left = Type.float(5.6);
    const right = Type.integer(3);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is greater than right float argument", () => {
    const left = Type.integer(5);
    const right = Type.float(3.2);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is greater than right integer argument", () => {
    const left = Type.integer(5);
    const right = Type.integer(3);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is equal to right float argument", () => {
    const left = Type.float(3.0);
    const right = Type.float(3.0);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left float argument is equal to right integer argument", () => {
    const left = Type.float(3.0);
    const right = Type.integer(3);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is equal to right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(3.0);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns true when left integer argument is equal to right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(3);
    const result = Erlang[">=/2"](left, right);

    assertBoxedTrue(result);
  });

  it("returns false when left float argument is smaller than right float argument", () => {
    const left = Type.float(3.2);
    const right = Type.float(5.6);
    const result = Erlang[">=/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left float argument is smaller than right integer argument", () => {
    const left = Type.float(3.2);
    const right = Type.integer(5);
    const result = Erlang[">=/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left integer argument is smaller than right float argument", () => {
    const left = Type.integer(3);
    const right = Type.float(5.6);
    const result = Erlang[">=/2"](left, right);

    assertBoxedFalse(result);
  });

  it("returns false when left integer argument is smaller than right integer argument", () => {
    const left = Type.integer(3);
    const right = Type.integer(5);
    const result = Erlang[">=/2"](left, right);

    assertBoxedFalse(result);
  });

  it("throws a not yet implemented error for non-integer and non-float left argument", () => {
    const left = Type.bitstring("abc");
    const right = Type.integer(2);

    const expectedMessage =
      'Structural comparison currently supports only floats and integers, got: "abc"';

    assert.throw(
      () => Erlang[">=/2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });

  it("throws a not yet implemented error for non-integer and non-float right argument", () => {
    const left = Type.integer(2);
    const right = Type.bitstring("abc");

    const expectedMessage =
      'Structural comparison currently supports only floats and integers, got: "abc"';

    assert.throw(
      () => Erlang[">=/2"](left, right),
      HologramInterpreterError,
      expectedMessage,
    );
  });
});

describe("andalso/2", () => {
  it("returns false if the first argument is false", () => {
    const vars = {left: Type.boolean(false), right: Type.atom("abc")};

    const result = Erlang["andalso/2"](
      (vars) => vars.left,
      (vars) => vars.right,
      vars,
    );

    assertBoxedFalse(result);
  });

  it("returns the second argument if the first argument is true", () => {
    const vars = {left: Type.boolean(true), right: Type.atom("abc")};

    const result = Erlang["andalso/2"](
      (vars) => vars.left,
      (vars) => vars.right,
      vars,
    );

    assert.deepStrictEqual(result, Type.atom("abc"));
  });

  it("doesn't evaluate the second argument if the first argument is false", () => {
    const result = Erlang["andalso/2"](
      (_vars) => Type.boolean(false),
      (_vars) => {
        throw new Error("impossible");
      },
      {},
    );

    assertBoxedFalse(result);
  });

  it("raises ArgumentError if the first argument is not a boolean", () => {
    const vars = {left: Type.nil(), right: Type.boolean(true)};

    assertBoxedError(
      () =>
        Erlang["andalso/2"](
          (vars) => vars.left,
          (vars) => vars.right,
          vars,
        ),
      "ArgumentError",
      "argument error: nil",
    );
  });
});

describe("atom_to_list/1", () => {
  it("empty atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom(""));
    assert.deepStrictEqual(result, Type.list([]));
  });

  it("ASCII atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom("abc"));

    assert.deepStrictEqual(
      result,
      Type.list([Type.integer(97), Type.integer(98), Type.integer(99)]),
    );
  });

  it("Unicode atom", () => {
    const result = Erlang["atom_to_list/1"](Type.atom("全息图"));

    assert.deepStrictEqual(
      result,
      Type.list([
        Type.integer(20840),
        Type.integer(24687),
        Type.integer(22270),
      ]),
    );
  });

  it("not an atom", () => {
    assertBoxedError(
      () => Erlang["atom_to_list/1"](Type.integer(123)),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
    );
  });
});

describe("atom_to_binary/1", () => {
  it("converts atom to (binary) bitstring", () => {
    const result = Erlang["atom_to_binary/1"](Type.atom("abc"));

    assert.deepStrictEqual(result, Type.bitstring("abc"));
  });

  it("raises ArgumentError if the argument is not an atom", () => {
    assertBoxedError(
      () => Erlang["atom_to_binary/1"](Type.integer(123)),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
    );
  });
});

describe("binary_to_atom/1", () => {
  it("delegates to binary_to_atom/2", () => {
    const binary = Type.bitstring("全息图");
    const result = Erlang["binary_to_atom/1"](binary);
    const expected = Erlang["binary_to_atom/2"](binary, Type.atom("utf8"));

    assert.deepStrictEqual(result, expected);
  });
});

describe("binary_to_atom/2", () => {
  const encoding = Type.atom("utf8");

  it("converts a binary bitstring to an already existing atom", () => {
    const binary = Type.bitstring("Elixir.Kernel");
    const result = Erlang["binary_to_atom/2"](binary, encoding);

    assert.deepStrictEqual(result, Type.alias("Kernel"));
  });

  it("converts a binary bitstring to a not existing yet atom", () => {
    const randomStr = `${Math.random()}`;
    const binary = Type.bitstring(randomStr);
    const result = Erlang["binary_to_atom/2"](binary, encoding);

    assert.deepStrictEqual(result, Type.atom(randomStr));
  });

  it("raises ArgumentError if the first argument is a non-binary bitstring", () => {
    assertBoxedError(
      () => Erlang["binary_to_atom/2"](Type.bitstring([1, 0, 1]), encoding),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
    );
  });

  it("raises ArgumentErorr if the first argument is not a bitstring", () => {
    assertBoxedError(
      () => Erlang["binary_to_atom/2"](Type.atom("abc"), encoding),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
    );
  });
});

describe("binary_to_existing_atom/1", () => {
  it("delegates to binary_to_atom/1", () => {
    const randomStr = `${Math.random()}`;
    const binary = Type.bitstring(randomStr);

    const result = Erlang["binary_to_existing_atom/1"](binary);
    const expected = Erlang["binary_to_atom/1"](binary);

    assert.deepStrictEqual(result, expected);
  });
});

describe("binary_to_existing_atom/2", () => {
  it("delegates to binary_to_atom/2", () => {
    const randomStr = `${Math.random()}`;
    const binary = Type.bitstring(randomStr);
    const encoding = Type.atom("utf8");

    const result = Erlang["binary_to_existing_atom/2"](binary, encoding);
    const expected = Erlang["binary_to_atom/2"](binary, encoding);

    assert.deepStrictEqual(result, expected);
  });
});

describe("bit_size/1", () => {
  it("bitstring", () => {
    const myBitstring = Type.bitstring([
      Type.bitstringSegment(Type.integer(2), {
        type: "integer",
        size: Type.integer(7),
      }),
    ]);

    const result = Erlang["bit_size/1"](myBitstring);

    assert.deepStrictEqual(result, Type.integer(7));
  });

  it("not bitstring", () => {
    const myAtom = Type.atom("abc");

    assertBoxedError(
      () => Erlang["bit_size/1"](myAtom),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not a bitstring\n",
    );
  });
});

describe("element/2", () => {
  const tuple = Type.tuple([Type.integer(5), Type.integer(6), Type.integer(7)]);

  it("returns the element at the one-based index in the tuple", () => {
    const result = Erlang["element/2"](Type.integer(2), tuple);
    assert.deepStrictEqual(result, Type.integer(6));
  });

  it("raises ArgumentError if the first argument is not an integer", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.atom("abc"), tuple),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
    );
  });

  it("raises ArgumentError if the second argument is not a tuple", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(1), Type.atom("abc")),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 2nd argument: not a tuple\n",
    );
  });

  it("raises ArgumentError if the given index is greater than the number of elements in the tuple", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(10), tuple),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: out of range\n",
    );
  });

  it("raises ArgumentError if the given index is smaller than 1", () => {
    assertBoxedError(
      () => Erlang["element/2"](Type.integer(0), tuple),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: out of range\n",
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

describe("integer_to_binary/1", () => {
  it("delegates to integer_to_binary/2", () => {
    const integer = Type.integer(123123);
    const result = Erlang["integer_to_binary/1"](integer);
    const expected = Erlang["integer_to_binary/2"](integer, Type.integer(10));

    assert.deepStrictEqual(result, expected);
  });
});

describe("integer_to_binary/2", () => {
  describe("positive integer", () => {
    it("base = 1", () => {
      assertBoxedError(
        () =>
          Erlang["integer_to_binary/2"](Type.integer(123123), Type.integer(1)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
      );
    });

    it("base = 2", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(2),
      );

      const expected = Type.bitstring("11110000011110011");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 16", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(16),
      );

      const expected = Type.bitstring("1E0F3");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 36", () => {
      const result = Erlang["integer_to_binary/2"](
        Type.integer(123123),
        Type.integer(36),
      );

      const expected = Type.bitstring("2N03");

      assert.deepStrictEqual(result, expected);
    });

    it("base = 37", () => {
      assertBoxedError(
        () =>
          Erlang["integer_to_binary/2"](Type.integer(123123), Type.integer(37)),
        "ArgumentError",
        "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
      );
    });
  });

  it("negative integer", () => {
    const result = Erlang["integer_to_binary/2"](
      Type.integer(-123123),
      Type.integer(16),
    );

    const expected = Type.bitstring("-1E0F3");

    assert.deepStrictEqual(result, expected);
  });

  it("1st argument (integer) is not an integer", () => {
    assertBoxedError(
      () => Erlang["integer_to_binary/2"](Type.atom("abc"), Type.integer(16)),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
    );
  });

  it("2nd argument (base) is not an integer", () => {
    assertBoxedError(
      () =>
        Erlang["integer_to_binary/2"](Type.integer(123123), Type.atom("abc")),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
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

describe("is_binary/1", () => {
  it("returns true if the term is a binary bitsting", () => {
    const term = Type.bitstring("abc");
    assertBoxedTrue(Erlang["is_binary/1"](term));
  });

  it("returns false if the term is a non-binary bitstring", () => {
    const term = Type.bitstring([0, 1, 0]);
    assertBoxedFalse(Erlang["is_binary/1"](term));
  });

  it("returns false if the term is not a bitstring", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_binary/1"](term));
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

describe("is_function/2", () => {
  it("returns true if the term is an anonymous function with the given arity", () => {
    const term = Type.anonymousFunction(3, ["dummy_clause"], {});
    assertBoxedTrue(Erlang["is_function/2"](term, Type.integer(3)));
  });

  it("returns false if the term is an anonymous function with a different arity", () => {
    const term = Type.anonymousFunction(3, ["dummy_clause"], {});
    assertBoxedFalse(Erlang["is_function/2"](term, Type.integer(4)));
  });

  it("returns false if the term is not an anonymous function", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_function/2"](term, Type.integer(3)));
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

describe("is_pid/1", () => {
  it("returns true if the term is a pid", () => {
    const term = Type.pid("0.11.222");
    assertBoxedTrue(Erlang["is_pid/1"](term));
  });

  it("returns false if the term is not a pid", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_pid/1"](term));
  });
});

describe("is_port/1", () => {
  it("returns true if the term is a port", () => {
    const term = Type.port("0.11");
    assertBoxedTrue(Erlang["is_port/1"](term));
  });

  it("returns false if the term is not a port", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_port/1"](term));
  });
});

describe("is_reference/1", () => {
  it("returns true if the term is a reference", () => {
    const term = Type.reference("0.1.2.3");
    assertBoxedTrue(Erlang["is_reference/1"](term));
  });

  it("returns false if the term is not a reference", () => {
    const term = Type.atom("abc");
    assertBoxedFalse(Erlang["is_reference/1"](term));
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

describe("orelse/2", () => {
  it("returns true if the first argument is true", () => {
    const vars = {left: Type.boolean(true), right: Type.atom("abc")};

    const result = Erlang["orelse/2"](
      (vars) => vars.left,
      (vars) => vars.right,
      vars,
    );

    assertBoxedTrue(result);
  });

  it("returns the second argument if the first argument is false", () => {
    const vars = {left: Type.boolean(false), right: Type.atom("abc")};

    const result = Erlang["orelse/2"](
      (vars) => vars.left,
      (vars) => vars.right,
      vars,
    );

    assert.deepStrictEqual(result, Type.atom("abc"));
  });

  it("doesn't evaluate the second argument if the first argument is true", () => {
    const result = Erlang["orelse/2"](
      (_vars) => Type.boolean(true),
      (_vars) => {
        throw new Error("impossible");
      },
      {},
    );

    assertBoxedTrue(result);
  });

  it("raises ArgumentError if the first argument is not a boolean", () => {
    const vars = {left: Type.nil(), right: Type.boolean(true)};

    assertBoxedError(
      () =>
        Erlang["orelse/2"](
          (vars) => vars.left,
          (vars) => vars.right,
          vars,
        ),
      "ArgumentError",
      "argument error: nil",
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

describe("tuple_to_list/1", () => {
  it("returns a list corresponding to the given tuple", () => {
    const data = [Type.integer(1), Type.integer(2), Type.integer(3)];
    const tuple = Type.tuple(data);

    const result = Erlang["tuple_to_list/1"](tuple);
    const expected = Type.list(data);

    assert.deepStrictEqual(result, expected);
  });

  it("raises ArgumentError if the argument is not a tuple", () => {
    assertBoxedError(
      () => Erlang["tuple_to_list/1"](Type.atom("abc")),
      "ArgumentError",
      "errors were found at the given arguments:\n\n  * 1st argument: not a tuple\n",
    );
  });
});
