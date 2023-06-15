"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

export default class Erlang {
  // start: +/2
  static $243(left, right) {
    const [type, leftValue, rightValue] =
      Erlang._ensureBothAreIntegersOrBothAreFloats(left, right);

    const result = leftValue.value + rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  }
  // end: +/2

  // start: -/2
  static $245(left, right) {
    const [type, leftValue, rightValue] =
      Erlang._ensureBothAreIntegersOrBothAreFloats(left, right);

    const result = leftValue.value - rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  }
  // end: -/2

  // start: /=/2
  static $247$261(left, right) {
    const isEqual = Erlang.$261$261(left, right);
    return Type.boolean(Type.isFalse(isEqual));
  }
  // end: /=/2

  // start: =:=/2
  static $261$258$261(left, right) {
    return Type.boolean(Interpreter.isStrictlyEqual(left, right));
  }
  // end: =:=/2

  // start: ==/2
  static $261$261(left, right) {
    let value;

    switch (left.type) {
      case "float":
      case "integer":
        if (Type.isNumber(left) && Type.isNumber(right)) {
          value = left.value == right.value;
        } else {
          value = false;
        }
        break;

      default:
        value = left.type === right.type && left.value === right.value;
        break;
    }

    return Type.boolean(value);
  }
  // end: ==/2

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // start: </2
  static $260(left, right) {
    if (
      (!Type.isFloat(left) && !Type.isInteger(left)) ||
      (!Type.isFloat(right) && !Type.isInteger(right))
    ) {
      const message =
        ":erlang.</2 currently supports only floats and integers" +
        ", left = " +
        Interpreter.inspect(left) +
        ", right = " +
        Interpreter.inspect(right);

      Interpreter.raiseNotYetImplementedError(message);
    }

    return Type.boolean(left.value < right.value);
  }
  // end: </2

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // start: >/2
  static $262(left, right) {
    if (
      (!Type.isFloat(left) && !Type.isInteger(left)) ||
      (!Type.isFloat(right) && !Type.isInteger(right))
    ) {
      const message =
        ":erlang.>/2 currently supports only floats and integers" +
        ", left = " +
        Interpreter.inspect(left) +
        ", right = " +
        Interpreter.inspect(right);

      Interpreter.raiseNotYetImplementedError(message);
    }

    return Type.boolean(left.value > right.value);
  }
  // end: >/2

  // start: hd/1
  static hd(list) {
    return Interpreter.head(list);
  }
  // end: hd/1

  // start: is_atom/1
  static is_atom(term) {
    return Type.boolean(Type.isAtom(term));
  }
  // end: is_atom/1

  // start: is_float/1
  static is_float(term) {
    return Type.boolean(Type.isFloat(term));
  }
  // end: is_float/1

  // start: is_integer/1
  static is_integer(term) {
    return Type.boolean(Type.isInteger(term));
  }
  // end: is_integer/1

  // start: is_number/1
  static is_number(term) {
    return Type.boolean(Type.isNumber(term));
  }
  // end: is_number/1

  // start: length/1
  static length(list) {
    return Type.integer(Interpreter.count(list));
  }
  // end: length/1

  // start: tl/1
  static tl(list) {
    return Interpreter.tail(list);
  }
  // end: tl/1

  static _ensureBothAreIntegersOrBothAreFloats(boxed1, boxed2) {
    const type =
      Type.isFloat(boxed1) || Type.isFloat(boxed2) ? "float" : "integer";

    let value1, value2;

    if (type === "float" && Type.isInteger(boxed1)) {
      value1 = Type.float(Number(boxed1.value));
    } else {
      value1 = boxed1;
    }

    if (type === "float" && Type.isInteger(boxed2)) {
      value2 = Type.float(Number(boxed2.value));
    } else {
      value2 = boxed2;
    }

    return [type, value1, value2];
  }
}
