"use strict";

import Hologram from "../hologram.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

/*
MFAs for sorting:
[
  {:erlang, :+, 2},
  {:erlang, :-, 2},
  {:erlang, :"/=", 2},
  {:erlang, :<, 2},
  {:erlang, :"=:=", 2},
  {:erlang, :==, 2},
  {:erlang, :>, 2},
  {:erlang, :error, 1},
  {:erlang, :error, 2},
  {:erlang, :hd, 1},
  {:erlang, :is_atom, 1},
  {:erlang, :is_float, 1},
  {:erlang, :is_integer, 1},
  {:erlang, :is_number, 1},
  {:erlang, :length, 1},
  {:erlang, :tl, 1},
  {:erlang, :==, 2}
]
|> Enum.sort()
*/

const Erlang = {
  // start +/2
  "+/2": (left, right) => {
    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value + rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // end +/2
  // deps: []

  // start -/2
  "-/2": (left, right) => {
    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value - rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // end -/2
  // deps: []

  // start /=/2
  "/=/2": (left, right) => {
    const isEqual = Erlang["==/2"](left, right);
    return Type.boolean(Type.isFalse(isEqual));
  },
  // end /=/2
  // deps: [:erlang.==/2]

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // start </2
  "</2": (left, right) => {
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
  // end </2
  // deps: []

  // start =:=/2
  "=:=/2": (left, right) => {
    return Type.boolean(Interpreter.isStrictlyEqual(left, right));
  },
  // end =:=/2
  // deps: []

  // start ==/2
  "==/2": (left, right) => {
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
  // end ==/2
  // deps: []

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // start >/2
  ">/2": (left, right) => {
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
  // end >/2
  // deps: []

  // TODO: review this function after error reporting is implemented
  // start error/1
  "error/1": (reason) => {
    Erlang["error/2"](reason, Type.atom("none"));
  },
  // end error/1
  // deps: []

  // TODO: review this function after error reporting is implemented
  // TODO: maybe use args param
  // start error/2
  "error/2": (reason, _args) => {
    throw new Error(`__hologram__:${Hologram.serialize(reason)}`);
  },
  // end error/2
  // deps: []

  // start hd/1
  "hd/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Hologram.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
      );
    }

    return list.data[0];
  },
  // end hd/1
  // deps: []

  // start is_atom/1
  "is_atom/1": (term) => {
    return Type.boolean(Type.isAtom(term));
  },
  // end is_atom/1
  // deps: []

  // start is_float/1
  "is_float/1": (term) => {
    return Type.boolean(Type.isFloat(term));
  },
  // end is_float/1
  // deps: []

  // start is_integer/1
  "is_integer/1": (term) => {
    return Type.boolean(Type.isInteger(term));
  },
  // end is_integer/1
  // deps: []

  // start is_number/1
  "is_number/1": (term) => {
    return Type.boolean(Type.isNumber(term));
  },
  // end is_number/1
  // deps: []

  // start length/1
  "length/1": (list) => {
    if (!Type.isList(list)) {
      Hologram.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a list",
      );
    }

    return Type.integer(list.data.length);
  },
  // end length/1
  // deps: []

  // start tl/1
  "tl/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Hologram.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
      );
    }

    const length = list.data.length;

    if (length === 1) {
      return Type.list([]);
    }

    const isProper = Type.isProperList(list);

    if (length === 2 && !isProper) {
      return list.data[1];
    }

    const data = list.data.slice(1);

    return isProper ? Type.list(data) : Type.improperList(data);
  },
  // end tl/1
  // deps: []
};

export default Erlang;
