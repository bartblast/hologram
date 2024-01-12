"use strict";

import Bitstring from "../bitstring.mjs";
import HologramBoxedError from "../errors/boxed_error.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in a "deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.Compiler.list_runtime_mfas/1.

/*
MFAs for sorting:
[
  {:erlang, :*, 2},
  {:erlang, :+, 2},
  {:erlang, :-, 2},
  {:erlang, :"/=", 2},
  {:erlang, :<, 2},
  {:erlang, :"=:=", 2},
  {:erlang, :"=<", 2},
  {:erlang, :==, 2},
  {:erlang, :>, 2},
  {:erlang, :>=, 2},
]
|> Enum.sort()
*/

const Erlang = {
  // start */2
  "*/2": (left, right) => {
    if (!Type.isNumber(left) || !Type.isNumber(right)) {
      Interpreter.raiseArgumentError(
        `bad argument in arithmetic expression: ${Interpreter.inspect(
          left,
        )} * ${Interpreter.inspect(right)}`,
      );
    }

    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value * rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // end */2
  // deps: []

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
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

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

  // start =</2
  "=</2": (left, right) => {
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

    const result =
      Type.isTrue(Erlang["==/2"](left, right)) ||
      Type.isTrue(Erlang["</2"](left, right));

    return Type.boolean(result);
  },
  // end =</2
  // deps: [:erlang.</2, :erlang.==/2]

  // start ==/2
  "==/2": (left, right) => {
    return Type.boolean(Interpreter.isEqual(left, right));
  },
  // end ==/2
  // deps: []

  // TODO: Implement structural comparison, see: https://hexdocs.pm/elixir/main/Kernel.html#module-structural-comparison
  // start >/2
  ">/2": (left, right) => {
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

    return Type.boolean(left.value > right.value);
  },
  // end >/2
  // deps: []

  // start >=/2
  ">=/2": (left, right) => {
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

    const result =
      Type.isTrue(Erlang["==/2"](left, right)) ||
      Type.isTrue(Erlang[">/2"](left, right));

    return Type.boolean(result);
  },
  // end >=/2
  // deps: [:erlang.==/2, :erlang.>/2]

  // start andalso/2
  "andalso/2": (leftFun, rightFun, vars) => {
    const left = leftFun(vars);

    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        `argument error: ${Interpreter.inspect(left)}`,
      );
    }

    return Type.isTrue(left) ? rightFun(vars) : left;
  },
  // end andalso/2
  // deps: []

  // start atom_to_binary/1
  "atom_to_binary/1": (atom) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
      );
    }

    return Type.bitstring(atom.value);
  },
  // end atom_to_binary/1
  // deps: []

  // start atom_to_list/1
  "atom_to_list/1": (atom) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not an atom\n",
      );
    }

    const codePoints = [...atom.value].map((cp) =>
      Type.integer(cp.codePointAt(0)),
    );

    return Type.list(codePoints);
  },
  // end atom_to_list/1
  // deps: []

  // start binary_to_atom/1
  "binary_to_atom/1": (binary) => {
    return Erlang["binary_to_atom/2"](binary, Type.atom("utf8"));
  },
  // end binary_to_atom/1
  // deps: [:erlang.binary_to_atom/2]

  // start binary_to_atom/2
  "binary_to_atom/2": (binary, encoding) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not a binary\n",
      );
    }

    // TODO: implement encoding argument validation

    // TODO: implement other encodings for encoding param
    if (!Interpreter.isStrictlyEqual(encoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    return Type.atom(Bitstring.toText(binary));
  },
  // end binary_to_atom/2
  // deps: []

  // Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  // The client version works exactly the same as binary_to_atom/1.
  // start binary_to_existing_atom/1
  "binary_to_existing_atom/1": (binary) => {
    return Erlang["binary_to_atom/1"](binary);
  },
  // end binary_to_existing_atom/1
  // deps: [:erlang.binary_to_atom/1]

  // Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  // The client version works exactly the same as binary_to_atom/2.
  // start binary_to_existing_atom/2
  "binary_to_existing_atom/2": (binary, encoding) => {
    return Erlang["binary_to_atom/2"](binary, encoding);
  },
  // end binary_to_existing_atom/2
  // deps: [:erlang.binary_to_atom/2]

  // start bit_size/1
  "bit_size/1": (term) => {
    if (!Type.isBitstring(term)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not a bitstring\n",
      );
    }

    return Type.integer(term.bits.length);
  },
  // end bit_size/1
  // deps: []

  // start element/2
  "element/2": (index, tuple) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
      );
    }

    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 2nd argument: not a tuple\n",
      );
    }

    if (index.value > tuple.data.length || index.value < 1) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: out of range\n",
      );
    }

    return tuple.data[Number(index.value) - 1];
  },
  // end element/2
  // deps: []

  // TODO: review this function after error reporting is implemented
  // start error/1
  "error/1": (reason) => {
    Erlang["error/2"](reason, Type.atom("none"));
  },
  // end error/1
  // deps: [:erlang.error/2]

  // TODO: review this function after error reporting is implemented
  // TODO: maybe use args param
  // start error/2
  "error/2": (reason, _args) => {
    throw new HologramBoxedError(reason);
  },
  // end error/2
  // deps: []

  // start hd/1
  "hd/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a nonempty list",
      );
    }

    return list.data[0];
  },
  // end hd/1
  // deps: []

  // start integer_to_binary/1
  "integer_to_binary/1": (integer) => {
    return Erlang["integer_to_binary/2"](integer, Type.integer(10));
  },
  // end integer_to_binary/1
  // deps: [:erlang.integer_to_binary/2]

  // start integer_to_binary/2
  "integer_to_binary/2": (integer, base) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not an integer\n",
      );
    }

    if (!Type.isInteger(base) || base.value < 2 || base.value > 36) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 2nd argument: not an integer in the range 2 through 36\n",
      );
    }

    const str = integer.value.toString(Number(base.value)).toUpperCase();

    return Type.bitstring(str);
  },
  // end integer_to_binary/2
  // deps: []

  // start is_atom/1
  "is_atom/1": (term) => {
    return Type.boolean(Type.isAtom(term));
  },
  // end is_atom/1
  // deps: []

  // start is_binary/1
  "is_binary/1": (term) => {
    return Type.boolean(Type.isBinary(term));
  },
  // end is_binary/1
  // deps: []

  // start is_bitstring/1
  "is_bitstring/1": (term) => {
    return Type.boolean(Type.isBitstring(term));
  },
  // end is_bitstring/1
  // deps: []

  // start is_float/1
  "is_float/1": (term) => {
    return Type.boolean(Type.isFloat(term));
  },
  // end is_float/1
  // deps: []

  // start is_function/1
  "is_function/1": (term) => {
    return Type.boolean(Type.isAnonymousFunction(term));
  },
  // end is_function/1
  // deps: []

  // start is_function/2
  "is_function/2": (term, arity) => {
    return Type.boolean(
      Type.isAnonymousFunction(term) && term.arity === Number(arity.value),
    );
  },
  // end is_function/2
  // deps: []

  // start is_integer/1
  "is_integer/1": (term) => {
    return Type.boolean(Type.isInteger(term));
  },
  // end is_integer/1
  // deps: []

  // start is_list/1
  "is_list/1": (term) => {
    return Type.boolean(Type.isList(term));
  },
  // end is_list/1
  // deps: []

  // start is_map/1
  "is_map/1": (term) => {
    return Type.boolean(Type.isMap(term));
  },
  // end is_map/1
  // deps: []

  // start is_number/1
  "is_number/1": (term) => {
    return Type.boolean(Type.isNumber(term));
  },
  // end is_number/1
  // deps: []

  // start is_pid/1
  "is_pid/1": (term) => {
    return Type.boolean(Type.isPid(term));
  },
  // end is_pid/1
  // deps: []

  // start is_port/1
  "is_port/1": (term) => {
    return Type.boolean(Type.isPort(term));
  },
  // end is_port/1
  // deps: []

  // start is_reference/1
  "is_reference/1": (term) => {
    return Type.boolean(Type.isReference(term));
  },
  // end is_reference/1
  // deps: []

  // start is_tuple/1
  "is_tuple/1": (term) => {
    return Type.boolean(Type.isTuple(term));
  },
  // end is_tuple/1
  // deps: []

  // start length/1
  "length/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n* 1st argument: not a list",
      );
    }

    return Type.integer(list.data.length);
  },
  // end length/1
  // deps: []

  // start map_size/1
  "map_size/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.integer(Object.keys(map.data).length);
  },
  // end map_size/1
  // deps: []

  // start orelse/2
  "orelse/2": (leftFun, rightFun, vars) => {
    const left = leftFun(vars);

    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        `argument error: ${Interpreter.inspect(left)}`,
      );
    }

    return Type.isTrue(left) ? left : rightFun(vars);
  },
  // end orelse/2
  // deps: []

  // start tl/1
  "tl/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseArgumentError(
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

  // start tuple_to_list/1
  "tuple_to_list/1": (tuple) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        "errors were found at the given arguments:\n\n  * 1st argument: not a tuple\n",
      );
    }

    return Type.list(tuple.data);
  },
  // end tuple_to_list/1
  // deps: []
};

export default Erlang;
