"use strict";

import Bitstring from "../bitstring.mjs";
import HologramBoxedError from "../errors/boxed_error.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Utils from "../utils.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

/*
MFAs for sorting:
[
  {:erlang, :*, 2},
  {:erlang, :+, 1},
  {:erlang, :+, 2},
  {:erlang, :++, 2},
  {:erlang, :-, 1},
  {:erlang, :-, 2},
  {:erlang, :--, 2},
  {:erlang, :/, 2},
  {:erlang, :"/=", 2},
  {:erlang, :<, 2},
  {:erlang, :"=/=", 2},
  {:erlang, :"=:=", 2},
  {:erlang, :"=<", 2},
  {:erlang, :==, 2},
  {:erlang, :>, 2},
  {:erlang, :>=, 2}
]
|> Enum.sort()
*/

const Erlang = {
  // Start */2
  "*/2": (left, right) => {
    if (!Type.isNumber(left) || !Type.isNumber(right)) {
      const blame = `${Interpreter.inspect(left)} * ${Interpreter.inspect(right)}`;
      Interpreter.raiseArithmeticError(blame);
    }

    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value * rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // End */2
  // Deps: []

  // Start +/2
  "+/2": (left, right) => {
    if (!Type.isNumber(left) || !Type.isNumber(right)) {
      const blame = `${Interpreter.inspect(left)} + ${Interpreter.inspect(right)}`;
      Interpreter.raiseArithmeticError(blame);
    }

    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value + rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // End +/2
  // Deps: []

  // Start +/1
  "+/1": (number) => {
    if (!Type.isNumber(number)) {
      const blame = `+(${Interpreter.inspect(number)})`;
      Interpreter.raiseArithmeticError(blame);
    }

    return number;
  },
  // End +/1
  // Deps: []

  // Start ++/2
  "++/2": (left, right) => {
    if (!Type.isProperList(left)) {
      Interpreter.raiseArgumentError("argument error");
    }

    const data = left.data.concat(Type.isList(right) ? right.data : [right]);

    return Type.isProperList(right) ? Type.list(data) : Type.improperList(data);
  },
  // End ++/2
  // Deps: []

  // Start -/1
  "-/1": (number) => {
    if (!Type.isNumber(number)) {
      const blame = `-(${Interpreter.inspect(number)})`;
      Interpreter.raiseArithmeticError(blame);
    }

    return number.value == 0 ? number : Type[number.type](-number.value);
  },
  // End -/1
  // Deps: []

  // Start -/2
  "-/2": (left, right) => {
    if (!Type.isNumber(left) || !Type.isNumber(right)) {
      const blame = `${Interpreter.inspect(left)} - ${Interpreter.inspect(right)}`;
      Interpreter.raiseArithmeticError(blame);
    }

    const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
      left,
      right,
    );

    const result = leftValue.value - rightValue.value;

    return type === "float" ? Type.float(result) : Type.integer(result);
  },
  // End -/2
  // Deps: []

  // TODO: optimize
  // This implementation is slow, i.e. O(m * n),
  // where m = Enum.count(left), n = Enum.count(right).
  // Start --/2
  "--/2": (left, right) => {
    if (!Type.isList(left) || !Type.isList(right)) {
      Interpreter.raiseArgumentError("argument error");
    }

    const result = Utils.shallowCloneArray(left.data);

    for (const rightElem of right.data) {
      for (let i = 0; i < result.length; ++i) {
        if (Interpreter.isStrictlyEqual(rightElem, result[i])) {
          result.splice(i, 1);
          break;
        }
      }
    }

    return Type.list(result);
  },
  // End --/2
  // Deps: []

  // Start //2
  "//2": (left, right) => {
    if (!Type.isNumber(left) || !Type.isNumber(right) || right.value == 0) {
      const blame = `${Interpreter.inspect(left)} / ${Interpreter.inspect(right)}`;
      Interpreter.raiseArithmeticError(blame);
    }

    return Type.float(Number(left.value) / Number(right.value));
  },
  // End //2
  // Deps: []

  // Start /=/2
  "/=/2": (left, right) => {
    return Type.boolean(!Interpreter.isEqual(left, right));
  },
  // End /=/2
  // Deps: []

  // Start </2
  "</2": (left, right) => {
    return Type.boolean(Interpreter.compareTerms(left, right) === -1);
  },
  // End </2
  // Deps: []

  // Start =/=/2
  "=/=/2": (left, right) => {
    return Type.boolean(!Interpreter.isStrictlyEqual(left, right));
  },
  // End =/=/2
  // Deps: []

  // Start =:=/2
  "=:=/2": (left, right) => {
    return Type.boolean(Interpreter.isStrictlyEqual(left, right));
  },
  // End =:=/2
  // Deps: []

  // Start =</2
  "=</2": (left, right) => {
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

    const result =
      Type.isTrue(Erlang["==/2"](left, right)) ||
      Type.isTrue(Erlang["</2"](left, right));

    return Type.boolean(result);
  },
  // End =</2
  // Deps: [:erlang.</2, :erlang.==/2]

  // Start ==/2
  "==/2": (left, right) => {
    return Type.boolean(Interpreter.isEqual(left, right));
  },
  // End ==/2
  // Deps: []

  // Start >/2
  ">/2": (left, right) => {
    return Type.boolean(Interpreter.compareTerms(left, right) === 1);
  },
  // End >/2
  // Deps: []

  // Start >=/2
  ">=/2": (left, right) => {
    Interpreter.assertStructuralComparisonSupportedType(left);
    Interpreter.assertStructuralComparisonSupportedType(right);

    const result =
      Type.isTrue(Erlang["==/2"](left, right)) ||
      Type.isTrue(Erlang[">/2"](left, right));

    return Type.boolean(result);
  },
  // End >=/2
  // Deps: [:erlang.==/2, :erlang.>/2]

  // Start abs/1
  "abs/1": (number) => {
    if (Type.isFloat(number)) {
      return Type.float(Math.abs(number.value));
    } else if (Type.isInteger(number)) {
      const value = number.value;
      return Type.integer(value < 0n ? -value : value);
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End abs/1
  // Deps: []

  // Start andalso/2
  "andalso/2": (leftFun, rightFun, context) => {
    const left = leftFun(context);

    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        `argument error: ${Interpreter.inspect(left)}`,
      );
    }

    return Type.isTrue(left) ? rightFun(context) : left;
  },
  // End andalso/2
  // Deps: []

  // :erlang.apply/3 calls are encoded as Interpreter.callNamedFuntion() calls.
  // See: https://github.com/bartblast/hologram/blob/4e832c722af7b0c1a0cca1c8c08287b999ecae78/lib/hologram/compiler/encoder.ex#L559

  // Start atom_to_binary/1
  "atom_to_binary/1": (atom) => {
    return Erlang["atom_to_binary/2"](atom, Type.atom("utf8"));
  },
  // End atom_to_binary/1
  // Deps: [:erlang.atom_to_binary/2]

  // Start atom_to_binary/2
  "atom_to_binary/2": (atom, encoding) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // TODO: implement encoding argument validation

    // TODO: implement other encodings for encoding param
    if (!Interpreter.isStrictlyEqual(encoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(atom.value);
  },
  // End atom_to_binary/2
  // Deps: []

  // Start atom_to_list/1
  "atom_to_list/1": (atom) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    return Bitstring.toCodepoints(Type.bitstring(atom.value));
  },
  // End atom_to_list/1
  // Deps: []

  // Start binary_to_atom/1
  "binary_to_atom/1": (binary) => {
    return Erlang["binary_to_atom/2"](binary, Type.atom("utf8"));
  },
  // End binary_to_atom/1
  // Deps: [:erlang.binary_to_atom/2]

  // Start binary_to_atom/2
  "binary_to_atom/2": (binary, encoding) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
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
  // End binary_to_atom/2
  // Deps: []

  // Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  // The client version works exactly the same as binary_to_atom/1.
  // Start binary_to_existing_atom/1
  "binary_to_existing_atom/1": (binary) => {
    return Erlang["binary_to_atom/1"](binary);
  },
  // End binary_to_existing_atom/1
  // Deps: [:erlang.binary_to_atom/1]

  // Note: due to practical reasons the behaviour of the client version is inconsistent with the server version.
  // The client version works exactly the same as binary_to_atom/2.
  // Start binary_to_existing_atom/2
  "binary_to_existing_atom/2": (binary, encoding) => {
    return Erlang["binary_to_atom/2"](binary, encoding);
  },
  // End binary_to_existing_atom/2
  // Deps: [:erlang.binary_to_atom/2]

  // Start binary_to_integer/1
  "binary_to_integer/1": (binary) => {
    return Erlang["binary_to_integer/2"](binary, Type.integer(10));
  },
  // End binary_to_integer/1
  // Deps: [:erlang.binary_to_integer/2]

  // Start binary_to_integer/2
  "binary_to_integer/2": (binary, base) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(base) || base.value < 2n || base.value > 36n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    }

    const text = Bitstring.toText(binary);
    const baseNum = Number(base.value);

    let validPattern;

    // Validate the text representation based on the base
    if (baseNum <= 10) {
      const maxDigit = String(baseNum - 1);
      validPattern = new RegExp(`^[+-]?[0-${maxDigit}]+$`);
    } else {
      const maxLetter = String.fromCharCode(65 + baseNum - 11); // A=10, B=11, etc.
      validPattern = new RegExp(`^[+-]?[0-9A-${maxLetter}]+$`, "i");
    }

    if (!validPattern.test(text)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of an integer",
        ),
      );
    }

    // For base 10, use BigInt directly to avoid precision loss
    // For other bases, use parseInt which handles the base conversion
    const result =
      baseNum === 10 ? BigInt(text) : BigInt(parseInt(text, baseNum));

    return Type.integer(result);
  },
  // End binary_to_integer/2
  // Deps: []

  // Start bit_size/1
  "bit_size/1": (term) => {
    if (!Type.isBitstring(term)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    return Type.integer(Bitstring.calculateBitCount(term));
  },
  // End bit_size/1
  // Deps: []

  // Start byte_size/1
  "byte_size/1": (bitstring) => {
    if (!Type.isBitstring(bitstring)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    Bitstring.maybeSetBytesFromText(bitstring);

    return Type.integer(bitstring.bytes.length);
  },
  // End byte_size/1
  // Deps: []

  // Start div/2
  "div/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArgumentError(
        `bad argument in arithmetic expression: div(${arg1}, ${arg2})`,
      );
    }

    if (integer2.value === 0n) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArithmeticError(`div(${arg1}, ${arg2})`);
    }

    // TODO: support integers outside Number range
    return Type.integer(
      Math.trunc(Number(integer1.value) / Number(integer2.value)),
    );
  },
  // End div/2
  // Deps: []

  // Start element/2
  "element/2": (index, tuple) => {
    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a tuple"),
      );
    }

    if (index.value > tuple.data.length || index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    return tuple.data[Number(index.value) - 1];
  },
  // End element/2
  // Deps: []

  // TODO: review this function after error reporting is implemented (and implement Elixir & JS consistency tests).
  // Start error/1
  "error/1": (reason) => {
    Erlang["error/2"](reason, Type.atom("none"));
  },
  // End error/1
  // Deps: [:erlang.error/2]

  // TODO: review this function after error reporting is implemented (and implement Elixir & JS consistency tests).
  // TODO: maybe use args param
  // Start error/2
  "error/2": (reason, _args) => {
    throw new HologramBoxedError(reason);
  },
  // End error/2
  // Deps: []

  // Start float_to_binary/2
  "float_to_binary/2": (float, opts) => {
    if (!Type.isFloat(float)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    }

    if (!Type.isList(opts)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isProperList(opts)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    // TODO: implement other options
    if (
      opts.data.length != 1 ||
      !Interpreter.isStrictlyEqual(opts.data[0], Type.atom("short"))
    ) {
      throw new HologramInterpreterError(
        ":erlang.float_to_binary/2 options other than :short are not yet implemented in Hologram",
      );
    }

    return Type.bitstring(float.value.toString());
  },
  // End float_to_binary/2
  // Deps: []

  // Start hd/1
  "hd/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
      );
    }

    return list.data[0];
  },
  // End hd/1
  // Deps: []

  // Start integer_to_binary/1
  "integer_to_binary/1": (integer) => {
    return Erlang["integer_to_binary/2"](integer, Type.integer(10));
  },
  // End integer_to_binary/1
  // Deps: [:erlang.integer_to_binary/2]

  // Start integer_to_binary/2
  "integer_to_binary/2": (integer, base) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(base) || base.value < 2 || base.value > 36) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    }

    const str = integer.value.toString(Number(base.value)).toUpperCase();

    return Type.bitstring(str);
  },
  // End integer_to_binary/2
  // Deps: []

  // TODO: test
  // Start iolist_to_binary/1
  "iolist_to_binary/1": (ioListOrBinary) => {
    // TODO: validate arg

    if (Type.isBitstring(ioListOrBinary)) {
      return ioListOrBinary;
    }

    const chunks = Erlang_Lists["flatten/1"](ioListOrBinary).data.map(
      (term) => {
        // TODO: validate list item (binary or integer allowed)

        if (Type.isBitstring(term)) {
          return term;
        }

        const segment = Type.bitstringSegment(term, {
          type: "integer",
          size: Type.integer(8),
          unit: 1n,
          endianness: "big",
        });

        return Bitstring.fromSegmentWithIntegerValue(segment);
      },
    );

    return Bitstring.concat(chunks);
  },
  // End iolist_to_binary/1
  // Deps: [:lists.flatten/1]

  // Start is_atom/1
  "is_atom/1": (term) => {
    return Type.boolean(Type.isAtom(term));
  },
  // End is_atom/1
  // Deps: []

  // Start is_binary/1
  "is_binary/1": (term) => {
    return Type.boolean(Type.isBinary(term));
  },
  // End is_binary/1
  // Deps: []

  // Start is_bitstring/1
  "is_bitstring/1": (term) => {
    return Type.boolean(Type.isBitstring(term));
  },
  // End is_bitstring/1
  // Deps: []

  // Start is_boolean/1
  "is_boolean/1": (term) => {
    return Type.boolean(Type.isBoolean(term));
  },
  // End is_boolean/1
  // Deps: []

  // Start is_float/1
  "is_float/1": (term) => {
    return Type.boolean(Type.isFloat(term));
  },
  // End is_float/1
  // Deps: []

  // Start is_function/1
  "is_function/1": (term) => {
    return Type.boolean(Type.isAnonymousFunction(term));
  },
  // End is_function/1
  // Deps: []

  // Start is_function/2
  "is_function/2": (term, arity) => {
    return Type.boolean(
      Type.isAnonymousFunction(term) && term.arity === Number(arity.value),
    );
  },
  // End is_function/2
  // Deps: []

  // Start is_integer/1
  "is_integer/1": (term) => {
    return Type.boolean(Type.isInteger(term));
  },
  // End is_integer/1
  // Deps: []

  // Start is_list/1
  "is_list/1": (term) => {
    return Type.boolean(Type.isList(term));
  },
  // End is_list/1
  // Deps: []

  // Start is_map/1
  "is_map/1": (term) => {
    return Type.boolean(Type.isMap(term));
  },
  // End is_map/1
  // Deps: []

  // Start is_number/1
  "is_number/1": (term) => {
    return Type.boolean(Type.isNumber(term));
  },
  // End is_number/1
  // Deps: []

  // Start is_pid/1
  "is_pid/1": (term) => {
    return Type.boolean(Type.isPid(term));
  },
  // End is_pid/1
  // Deps: []

  // Start is_port/1
  "is_port/1": (term) => {
    return Type.boolean(Type.isPort(term));
  },
  // End is_port/1
  // Deps: []

  // Start is_reference/1
  "is_reference/1": (term) => {
    return Type.boolean(Type.isReference(term));
  },
  // End is_reference/1
  // Deps: []

  // Start is_tuple/1
  "is_tuple/1": (term) => {
    return Type.boolean(Type.isTuple(term));
  },
  // End is_tuple/1
  // Deps: []

  // Start length/1
  "length/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.integer(list.data.length);
  },
  // End length/1
  // Deps: []

  // Start list_to_pid/1
  "list_to_pid/1": (codePoints) => {
    if (!Type.isList(codePoints)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    const areCodePointsValid = codePoints.data.every(
      (item) => Type.isInteger(item) && Bitstring.validateCodePoint(item.value),
    );

    if (!areCodePointsValid) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a pid",
        ),
      );
    }

    const segments = codePoints.data.map((codePoint) =>
      Type.bitstringSegment(codePoint, {type: "utf8"}),
    );

    const regex = /^<([0-9]+)\.([0-9]+)\.([0-9]+)>$/;
    const matches = Bitstring.toText(Type.bitstring(segments)).match(regex);

    if (matches === null) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a pid",
        ),
      );
    }

    return Type.pid(
      "client",
      [Number(matches[1]), Number(matches[2]), Number(matches[3])],
      "client",
    );
  },
  // End list_to_pid/1
  // Deps: []

  // Start map_size/1
  "map_size/1": (map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    return Type.integer(Object.keys(map.data).length);
  },
  // End map_size/1
  // Deps: []

  // TODO: test
  // Start max/2
  "max/2": (term1, term2) => {
    switch (Interpreter.compareTerms(term1, term2)) {
      case -1:
        return term2;

      case 0:
        return term1;

      case 1:
        return term1;
    }
  },
  // End max/2
  // Deps: []

  // TODO: test
  // Start min/2
  "min/2": (term1, term2) => {
    switch (Interpreter.compareTerms(term1, term2)) {
      case -1:
        return term1;

      case 0:
        return term1;

      case 1:
        return term2;
    }
  },
  // End min/2
  // Deps: []

  // Start not/1
  "not/1": (term) => {
    if (!Type.isBoolean(term)) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.boolean(term.value == "true" ? false : true);
  },
  // End not/1
  // Deps: []

  // Start orelse/2
  "orelse/2": (leftFun, rightFun, context) => {
    const left = leftFun(context);

    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        `argument error: ${Interpreter.inspect(left)}`,
      );
    }

    return Type.isTrue(left) ? left : rightFun(context);
  },
  // End orelse/2
  // Deps: []

  // Start rem/2
  "rem/2": (integer1, integer2) => {
    if (
      !Type.isInteger(integer1) ||
      !Type.isInteger(integer2) ||
      integer2.value === 0n
    ) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArithmeticError(`rem(${arg1}, ${arg2})`);
    }

    // JavaScript's % operator on BigInt has the same sign behavior as Erlang's rem
    // The result has the same sign as the dividend (integer1)
    return Type.integer(integer1.value % integer2.value);
  },
  // End rem/2
  // Deps: []

  // Start split_binary/2
  "split_binary/2": (binary, position) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(position)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (position.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    const pos = Number(position.value);
    const totalBytes = Number(Erlang["byte_size/1"](binary).value);

    if (pos > totalBytes) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    // If position is 0, first part is empty binary
    if (pos === 0) {
      return Type.tuple([Type.bitstring(""), binary]);
    }

    // If position equals total size, second part is empty binary
    if (pos === totalBytes) {
      return Type.tuple([binary, Type.bitstring("")]);
    }

    // Split the binary using takeChunk
    // First part: from start to position (pos bytes)
    const firstPart = Bitstring.takeChunk(binary, 0, pos * 8);

    // Second part: from position to end
    const secondPart = Bitstring.takeChunk(
      binary,
      pos * 8,
      (totalBytes - pos) * 8,
    );

    return Type.tuple([firstPart, secondPart]);
  },
  // End split_binary/2
  // Deps: [:erlang.byte_size/1]

  // Start tl/1
  "tl/1": (list) => {
    if (!Type.isList(list) || list.data.length === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a nonempty list"),
      );
    }

    const length = list.data.length;

    if (length === 1) {
      return Type.list();
    }

    const isProper = Type.isProperList(list);

    if (length === 2 && !isProper) {
      return list.data[1];
    }

    const data = list.data.slice(1);

    return isProper ? Type.list(data) : Type.improperList(data);
  },
  // End tl/1
  // Deps: []

  // Start tuple_to_list/1
  "tuple_to_list/1": (tuple) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    return Type.list(tuple.data);
  },
  // End tuple_to_list/1
  // Deps: []
  // Start list_to_tuple/1
  "list_to_tuple/1": (list) => {
    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    return Type.tuple(list.data);
  },
  // End list_to_tuple/1
  // Deps: []
};

export default Erlang;
