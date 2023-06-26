"use strict";

import Hologram from "../hologram.mjs";

const Interpreter = Hologram.Interpreter;
const Type = Hologram.Type;

const Erlang = {
  // supported arities: 2
  // start: +
  $243: (left, right) => {
    const [type, leftValue, rightValue] =
      Erlang._ensureBothAreIntegersOrBothAreFloats(left, right);

    const result = leftValue.value + rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // end: +

  // supported arities: 2
  // start: -
  $245: (left, right) => {
    const [type, leftValue, rightValue] =
      Erlang._ensureBothAreIntegersOrBothAreFloats(left, right);

    const result = leftValue.value - rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // end: -

  // supported arities: 2
  // start: /=
  $247$261: (left, right) => {
    const isEqual = Erlang.$261$261(left, right);
    return Type.boolean(Type.isFalse(isEqual));
  },
  // end: /=

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // supported arities: 2
  // start: <
  $260: (left, right) => {
    if (
      (!Type.isFloat(left) && !Type.isInteger(left)) ||
      (!Type.isFloat(right) && !Type.isInteger(right))
    ) {
      const message =
        ":erlang.</2 currently supports only floats and integers" +
        ", left = " +
        Hologram.inspect(left) +
        ", right = " +
        Hologram.inspect(right);

      Hologram.raiseInterpreterError(message);
    }

    return Type.boolean(left.value < right.value);
  },
  // end: <

  // supported arities: 2
  // start: =:=
  $261$258$261: (left, right) => {
    return Type.boolean(Interpreter.isStrictlyEqual(left, right));
  },
  // end: =:=

  // supported arities: 2
  // start: ==
  $261$261: (left, right) => {
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
  },
  // end: ==

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // supported arities: 2
  // start: >
  $262: (left, right) => {
    if (
      (!Type.isFloat(left) && !Type.isInteger(left)) ||
      (!Type.isFloat(right) && !Type.isInteger(right))
    ) {
      const message =
        ":erlang.>/2 currently supports only floats and integers" +
        ", left = " +
        Hologram.inspect(left) +
        ", right = " +
        Hologram.inspect(right);

      Hologram.raiseInterpreterError(message);
    }

    return Type.boolean(left.value > right.value);
  },
  // end: >

  // TODO: error/2
  // supported arities: 1
  // start: error
  error: (reason) => {
    throw new Error(`__hologram__:${Hologram.serialize(reason)}`);
  },
  // end: error

  // supported arities: 1
  // start: hd
  hd: (list) => {
    if (!Type.isList(list) || Erlang.length(list).value === 0n) {
      Hologram.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list"
      );
    }

    return list.data[0];
  },
  // end: hd

  // supported arities: 1
  // start: is_atom
  is_atom: (term) => {
    return Type.boolean(Type.isAtom(term));
  },
  // end: is_atom

  // supported arities: 1
  // start: is_float
  is_float: (term) => {
    return Type.boolean(Type.isFloat(term));
  },
  // end: is_float

  // supported arities: 1
  // start: is_integer
  is_integer: (term) => {
    return Type.boolean(Type.isInteger(term));
  },
  // end: is_integer

  // supported arities: 1
  // start: is_number
  is_number: (term) => {
    return Type.boolean(Type.isNumber(term));
  },
  // end: is_number

  // supported arities: 1
  // start: length
  length: (list) => {
    if (!Type.isList(list)) {
      Hologram.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a list"
      );
    }

    return Type.integer(list.data.length);
  },
  // end: length

  // supported arities: 1
  // start: tl
  tl: (list) => {
    return Interpreter.tail(list);
  },
  // end: tl

  _ensureBothAreIntegersOrBothAreFloats: (boxed1, boxed2) => {
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
  },
};

export default Erlang;
