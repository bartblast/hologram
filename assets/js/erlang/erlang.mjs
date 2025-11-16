"use strict";

import Bitstring from "../bitstring.mjs";
import HologramBoxedError from "../errors/boxed_error.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Sequence from "../sequence.mjs";
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

// Simple process dictionary (client-side only has single "process")
const ProcessDictionary = new Map();

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

  // Start and/2
  "and/2": (left, right) => {
    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(right)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    return Type.boolean(Type.isTrue(left) && Type.isTrue(right));
  },
  // End and/2
  // Deps: []

  // Start append_element/2
  "append_element/2": (tuple, term) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    const newData = [...tuple.data, term];
    return Type.tuple(newData);
  },
  // End append_element/2
  // Deps: []

  // Start apply/2
  "apply/2": (fun, args) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    if (!Type.isProperList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a proper list"),
      );
    }

    return Interpreter.callAnonymousFunction(fun, args.data);
  },
  // End apply/2
  // Deps: []

  // Start apply/3
  "apply/3": (module, functionName, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(functionName)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    if (!Type.isProperList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a proper list"),
      );
    }

    const context = Interpreter.buildContext({
      module: Type.atom("Elixir.Erlang"),
      vars: {},
    });
    return Interpreter.callNamedFunction(module, functionName, args, context);
  },
  // End apply/3
  // Deps: []

  // Note: :erlang.apply/3 calls are often encoded as Interpreter.callNamedFunction() calls.
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

  // Start binary_to_float/1
  "binary_to_float/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetTextFromBytes(binary);
    const text = binary.text;

    // Validate that the text represents a valid float
    // Erlang requires floats to have decimal point or exponent
    if (!/^[+-]?\d+\.\d+([eE][+-]?\d+)?$|^[+-]?\d+[eE][+-]?\d+$/.test(text)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a textual representation of a float"),
      );
    }

    const value = parseFloat(text);

    if (!isFinite(value)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a textual representation of a float"),
      );
    }

    return Type.float(value);
  },
  // End binary_to_float/1
  // Deps: []

  // Start bnot/1
  "bnot/1": (integer) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: bnot ${Interpreter.inspect(integer)}`,
      );
    }

    return Type.integer(~integer.value);
  },
  // End bnot/1
  // Deps: []

  // Start bor/2
  "bor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: ${arg1} bor ${arg2}`,
      );
    }

    return Type.integer(integer1.value | integer2.value);
  },
  // End bor/2
  // Deps: []

  // Start bsl/2
  "bsl/2": (integer, shift) => {
    if (!Type.isInteger(integer) || !Type.isInteger(shift)) {
      const arg1 = Interpreter.inspect(integer);
      const arg2 = Interpreter.inspect(shift);

      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: ${arg1} bsl ${arg2}`,
      );
    }

    return Type.integer(integer.value << shift.value);
  },
  // End bsl/2
  // Deps: []

  // Start bsr/2
  "bsr/2": (integer, shift) => {
    if (!Type.isInteger(integer) || !Type.isInteger(shift)) {
      const arg1 = Interpreter.inspect(integer);
      const arg2 = Interpreter.inspect(shift);

      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: ${arg1} bsr ${arg2}`,
      );
    }

    return Type.integer(integer.value >> shift.value);
  },
  // End bsr/2
  // Deps: []

  // Start bxor/2
  "bxor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: ${arg1} bxor ${arg2}`,
      );
    }

    return Type.integer(integer1.value ^ integer2.value);
  },
  // End bxor/2
  // Deps: []

  // Start binary_to_list/1
  "binary_to_list/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = Array.from(binary.bytes);
    const data = bytes.map((byte) => Type.integer(byte));

    return Type.list(data);
  },
  // End binary_to_list/1
  // Deps: []

  // Start binary_to_list/3
  "binary_to_list/3": (binary, start, stop) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(start)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(stop)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const byteSize = binary.bytes.length;

    // Erlang uses 1-based indexing
    const startIdx = Number(start.value) - 1;
    const stopIdx = Number(stop.value);

    if (startIdx < 0 || startIdx >= byteSize) {
      Interpreter.raiseArgumentError("start index out of range");
    }

    if (stopIdx < 1 || stopIdx > byteSize) {
      Interpreter.raiseArgumentError("stop index out of range");
    }

    if (startIdx >= stopIdx) {
      Interpreter.raiseArgumentError("start must be less than or equal to stop");
    }

    const bytes = Array.from(binary.bytes.slice(startIdx, stopIdx));
    const data = bytes.map((byte) => Type.integer(byte));

    return Type.list(data);
  },
  // End binary_to_list/3
  // Deps: []

  // Start binary_part/2
  "binary_part/2": (binary, posLength) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isTuple(posLength) || posLength.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid {Pos, Length} tuple"),
      );
    }

    const pos = posLength.data[0];
    const length = posLength.data[1];

    if (!Type.isInteger(pos) || !Type.isInteger(length)) {
      Interpreter.raiseArgumentError("arguments must be integers");
    }

    return Erlang["binary_part/3"](binary, pos, length);
  },
  // End binary_part/2
  // Deps: [:erlang.binary_part/3]

  // Start binary_part/3
  "binary_part/3": (binary, pos, length) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(pos)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(length)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const byteSize = binary.bytes.length;
    const posNum = Number(pos.value);
    const lengthNum = Number(length.value);

    // Handle negative position (count from end)
    const actualPos = posNum < 0 ? byteSize + posNum : posNum;

    if (actualPos < 0 || actualPos > byteSize) {
      Interpreter.raiseArgumentError("position out of range");
    }

    if (lengthNum < 0) {
      Interpreter.raiseArgumentError("length must be non-negative");
    }

    if (actualPos + lengthNum > byteSize) {
      Interpreter.raiseArgumentError("position + length out of range");
    }

    // Extract the substring
    const partBytes = binary.bytes.slice(actualPos, actualPos + lengthNum);
    const partText = new TextDecoder().decode(new Uint8Array(partBytes));

    return Type.bitstring(partText);
  },
  // End binary_part/3
  // Deps: []

  // Start band/2
  "band/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArgumentError(
        `bad argument in bitwise expression: ${arg1} band ${arg2}`,
      );
    }

    return Type.integer(integer1.value & integer2.value);
  },
  // End band/2
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

  // Start ceil/1
  "ceil/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (Type.isInteger(number)) {
      return number;
    }

    return Type.integer(Math.ceil(number.value));
  },
  // End ceil/1
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

  // Start delete_element/2
  "delete_element/2": (index, tuple) => {
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

    const indexNum = Number(index.value);
    const tupleSize = tuple.data.length;

    if (indexNum < 1 || indexNum > tupleSize) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    // Remove element at index (1-based)
    const newData = tuple.data.filter((_, i) => i !== indexNum - 1);
    return Type.tuple(newData);
  },
  // End delete_element/2
  // Deps: []

  // Start date/0
  "date/0": () => {
    const now = new Date();
    return Type.tuple([
      Type.integer(BigInt(now.getFullYear())),
      Type.integer(BigInt(now.getMonth() + 1)), // JavaScript months are 0-indexed
      Type.integer(BigInt(now.getDate())),
    ]);
  },
  // End date/0
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

  // Start exit/1
  "exit/1": (reason) => {
    throw new HologramBoxedError(reason);
  },
  // End exit/1
  // Deps: []

  // Start erase/0
  "erase/0": () => {
    const entries = [];
    for (const [key, value] of ProcessDictionary.entries()) {
      entries.push(Type.tuple([key, value]));
    }
    ProcessDictionary.clear();
    return Type.list(entries);
  },
  // End erase/0
  // Deps: []

  // Start erase/1
  "erase/1": (key) => {
    const encodedKey = Type.encodeMapKey(key);
    const value = ProcessDictionary.get(encodedKey);
    ProcessDictionary.delete(encodedKey);
    return value !== undefined ? value[1] : Type.atom("undefined");
  },
  // End erase/1
  // Deps: []

  // Start get/0
  "get/0": () => {
    const entries = [];
    for (const [encodedKey, value] of ProcessDictionary.entries()) {
      // Decode the key back (simplified - just store original key with value)
      entries.push(Type.tuple([value[0], value[1]]));
    }
    return Type.list(entries);
  },
  // End get/0
  // Deps: []

  // Start get/1
  "get/1": (key) => {
    const encodedKey = Type.encodeMapKey(key);
    const value = ProcessDictionary.get(encodedKey);
    return value !== undefined ? value[1] : Type.atom("undefined");
  },
  // End get/1
  // Deps: []

  // Start get_keys/0
  "get_keys/0": () => {
    const keys = [];
    for (const [encodedKey, value] of ProcessDictionary.entries()) {
      keys.push(value[0]); // Original key
    }
    return Type.list(keys);
  },
  // End get_keys/0
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

  // Start floor/1
  "floor/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (Type.isInteger(number)) {
      return number;
    }

    return Type.integer(Math.floor(number.value));
  },
  // End floor/1
  // Deps: []

  // Start float/1
  "float/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (Type.isFloat(number)) {
      return number;
    }

    return Type.float(Number(number.value));
  },
  // End float/1
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

  // Start integer_to_list/1
  "integer_to_list/1": (integer) => {
    return Erlang["integer_to_list/2"](integer, Type.integer(10));
  },
  // End integer_to_list/1
  // Deps: [:erlang.integer_to_list/2]

  // Start integer_to_list/2
  "integer_to_list/2": (integer, base) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(base)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const baseNum = Number(base.value);

    if (baseNum < 2 || baseNum > 36) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    }

    const intValue = integer.value;
    let text;

    if (baseNum === 10) {
      text = intValue.toString();
    } else {
      // For other bases, convert to string in that base
      // BigInt toString supports radix
      text = intValue.toString(baseNum);
    }

    // Convert to list of character codes
    return Bitstring.toCodepoints(Type.bitstring(text));
  },
  // End integer_to_list/2
  // Deps: []

  // Start insert_element/3
  "insert_element/3": (index, tuple, term) => {
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

    const indexNum = Number(index.value);
    const tupleSize = tuple.data.length;

    // In Erlang, insert_element allows inserting at position 1 to size+1
    if (indexNum < 1 || indexNum > tupleSize + 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    // Insert element at index (1-based)
    const newData = [
      ...tuple.data.slice(0, indexNum - 1),
      term,
      ...tuple.data.slice(indexNum - 1),
    ];

    return Type.tuple(newData);
  },
  // End insert_element/3
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

  // Start iolist_size/1
  "iolist_size/1": (iolist) => {
    // Convert iolist to binary and get its size
    const binary = Erlang["iolist_to_binary/1"](iolist);
    return Erlang["byte_size/1"](binary);
  },
  // End iolist_size/1
  // Deps: [:erlang.iolist_to_binary/1, :erlang.byte_size/1]

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

  // Start list_to_tuple/1
  "list_to_tuple/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    return Type.tuple(list.data);
  },
  // End list_to_tuple/1
  // Deps: []

  // Start list_to_binary/1
  "list_to_binary/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    // Validate that all elements are integers in valid byte range (0-255)
    for (const elem of list.data) {
      if (!Type.isInteger(elem)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a list of bytes"),
        );
      }

      const value = Number(elem.value);
      if (value < 0 || value > 255) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a list of bytes"),
        );
      }
    }

    // Convert list of integers to string using character codes
    const text = String.fromCharCode(...list.data.map((elem) => Number(elem.value)));

    return Type.bitstring(text);
  },
  // End list_to_binary/1
  // Deps: []

  // Start list_to_atom/1
  "list_to_atom/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    // Validate that all elements are valid character codes
    for (const elem of list.data) {
      if (!Type.isInteger(elem)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a textual representation of an atom"),
        );
      }

      const value = Number(elem.value);
      if (!Bitstring.validateCodePoint(value)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a textual representation of an atom"),
        );
      }
    }

    // Convert list of integers to string
    const text = String.fromCharCode(...list.data.map((elem) => Number(elem.value)));

    return Type.atom(text);
  },
  // End list_to_atom/1
  // Deps: []

  // Start list_to_existing_atom/1
  "list_to_existing_atom/1": (list) => {
    // Note: In Hologram, we cannot check if an atom "exists" at runtime
    // as atoms are created on-demand. This function behaves the same as list_to_atom/1
    return Erlang["list_to_atom/1"](list);
  },
  // End list_to_existing_atom/1
  // Deps: [:erlang.list_to_atom/1]

  // Start list_to_float/1
  "list_to_float/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    // Convert list to binary first, then use binary_to_float
    const binary = Erlang["list_to_binary/1"](list);
    return Erlang["binary_to_float/1"](binary);
  },
  // End list_to_float/1
  // Deps: [:erlang.list_to_binary/1, :erlang.binary_to_float/1]

  // Start list_to_integer/1
  "list_to_integer/1": (list) => {
    return Erlang["list_to_integer/2"](list, Type.integer(10));
  },
  // End list_to_integer/1
  // Deps: [:erlang.list_to_integer/2]

  // Start list_to_integer/2
  "list_to_integer/2": (list, base) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    // Convert list to binary first, then use binary_to_integer
    const binary = Erlang["list_to_binary/1"](list);
    return Erlang["binary_to_integer/2"](binary, base);
  },
  // End list_to_integer/2
  // Deps: [:erlang.list_to_binary/1, :erlang.binary_to_integer/2]

  // Start localtime/0
  "localtime/0": () => {
    const now = new Date();
    const date = Type.tuple([
      Type.integer(BigInt(now.getFullYear())),
      Type.integer(BigInt(now.getMonth() + 1)),
      Type.integer(BigInt(now.getDate())),
    ]);
    const time = Type.tuple([
      Type.integer(BigInt(now.getHours())),
      Type.integer(BigInt(now.getMinutes())),
      Type.integer(BigInt(now.getSeconds())),
    ]);
    return Type.tuple([date, time]);
  },
  // End localtime/0
  // Deps: []

  // Start convert_time_unit/3
  "convert_time_unit/3": (time, fromUnit, toUnit) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    const getMultiplier = (unit) => {
      if (Type.isInteger(unit)) {
        return unit.value;
      }
      if (!Type.isAtom(unit)) {
        Interpreter.raiseArgumentError("invalid time unit");
      }
      switch (unit.value) {
        case "second": return 1000000000n;
        case "millisecond": return 1000000n;
        case "microsecond": return 1000n;
        case "nanosecond": return 1n;
        case "native": return 1000n; // Assume microsecond precision
        case "perf_counter": return 1000n;
        default:
          Interpreter.raiseArgumentError("invalid time unit");
      }
    };

    const fromMult = getMultiplier(fromUnit);
    const toMult = getMultiplier(toUnit);

    // Convert: time * fromMult / toMult
    const result = (time.value * fromMult) / toMult;
    return Type.integer(result);
  },
  // End convert_time_unit/3
  // Deps: []

  // Start float_to_list/1
  "float_to_list/1": (float) => {
    return Erlang["float_to_list/2"](float, Type.list([]));
  },
  // End float_to_list/1
  // Deps: [:erlang.float_to_list/2]

  // Start float_to_list/2
  "float_to_list/2": (float, options) => {
    if (!Type.isFloat(float)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // For simplicity, use default formatting
    // Full implementation would parse options for scientific notation, decimals, etc.
    const str = float.value.toString();
    const codePoints = [];
    for (let i = 0; i < str.length; i++) {
      codePoints.push(Type.integer(BigInt(str.charCodeAt(i))));
    }
    return Type.list(codePoints);
  },
  // End float_to_list/2
  // Deps: []

  // Start fun_info/1
  "fun_info/1": (fun) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    const arity = Type.tuple([Type.atom("arity"), Type.integer(fun.arity)]);
    const env = Type.tuple([Type.atom("env"), Type.list([])]);
    const index = Type.tuple([Type.atom("index"), Type.integer(0)]);
    const name = Type.tuple([
      Type.atom("name"),
      fun.capturedFunction || Type.atom("anonymous"),
    ]);
    const module = Type.tuple([
      Type.atom("module"),
      fun.capturedModule || Type.atom("erl_eval"),
    ]);
    const newIndex = Type.tuple([
      Type.atom("new_index"),
      Type.integer(fun.uniqueId),
    ]);
    const newUniq = Type.tuple([Type.atom("new_uniq"), Type.integer(0)]);
    const pid = Type.tuple([
      Type.atom("pid"),
      Type.pid(Type.atom("nonode@nohost"), [0, 0, 0], "client"),
    ]);
    const type = Type.tuple([Type.atom("type"), Type.atom("local")]);
    const uniq = Type.tuple([Type.atom("uniq"), Type.integer(0)]);

    return Type.list([
      arity,
      env,
      index,
      module,
      name,
      newIndex,
      newUniq,
      pid,
      type,
      uniq,
    ]);
  },
  // End fun_info/1
  // Deps: []

  // Start fun_info/2
  "fun_info/2": (fun, item) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    switch (item.value) {
      case "arity":
        return Type.tuple([Type.atom("arity"), Type.integer(fun.arity)]);

      case "env":
        return Type.tuple([Type.atom("env"), Type.list([])]);

      case "index":
        return Type.tuple([Type.atom("index"), Type.integer(0)]);

      case "module":
        return Type.tuple([
          Type.atom("module"),
          fun.capturedModule || Type.atom("erl_eval"),
        ]);

      case "name":
        return Type.tuple([
          Type.atom("name"),
          fun.capturedFunction || Type.atom("anonymous"),
        ]);

      case "new_index":
        return Type.tuple([
          Type.atom("new_index"),
          Type.integer(fun.uniqueId),
        ]);

      case "new_uniq":
        return Type.tuple([Type.atom("new_uniq"), Type.integer(0)]);

      case "pid":
        return Type.tuple([
          Type.atom("pid"),
          Type.pid(Type.atom("nonode@nohost"), [0, 0, 0], "client"),
        ]);

      case "type":
        return Type.tuple([Type.atom("type"), Type.atom("local")]);

      case "uniq":
        return Type.tuple([Type.atom("uniq"), Type.integer(0)]);

      default:
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "invalid item"),
        );
    }
  },
  // End fun_info/2
  // Deps: []

  // Start function_exported/3
  "function_exported/3": (module, functionName, arity) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(functionName)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isInteger(arity)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    const moduleProxy = Interpreter.moduleProxy(module);
    if (typeof moduleProxy === "undefined") {
      return Type.boolean(false);
    }

    const functionArityStr = `${functionName.value}/${arity.value}`;
    const hasFunction =
      moduleProxy.__exports__ && moduleProxy.__exports__.has(functionArityStr);
    return Type.boolean(Boolean(hasFunction));
  },
  // End function_exported/3
  // Deps: []

  // Start is_map_key/2
  "is_map_key/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const keyString = Type.encodeMapKey(key);
    return Type.boolean(keyString in map.data);
  },
  // End is_map_key/2
  // Deps: []

  // Start map_get/2
  "map_get/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const keyString = Type.encodeMapKey(key);
    if (!(keyString in map.data)) {
      const message = `key ${Interpreter.inspect(key)} not found in: ${Interpreter.inspect(map)}`;
      Interpreter.raiseError("BadKeyError", message);
    }

    return map.data[keyString][1]; // Return value part of [key, value]
  },
  // End map_get/2
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

  // Start make_tuple/2
  "make_tuple/2": (size, defaultValue) => {
    if (!Type.isInteger(size)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (size.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid tuple size"),
      );
    }

    const length = Number(size.value);
    const data = new Array(length).fill(defaultValue);

    return Type.tuple(data);
  },
  // End make_tuple/2
  // Deps: []

  // Start make_ref/0
  "make_ref/0": () => {
    const id = Sequence.next();
    return Type.reference(
      Type.atom("nonode@nohost"),
      [0, 0, id],
      "client",
    );
  },
  // End make_ref/0
  // Deps: []

  // Start make_fun/3
  "make_fun/3": (module, functionName, arity) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(functionName)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isInteger(arity)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    if (arity.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a valid arity"),
      );
    }

    // Verify the function exists
    const moduleProxy = Interpreter.moduleProxy(module);
    if (typeof moduleProxy === "undefined") {
      Interpreter.raiseError(
        "FunctionClauseError",
        `no function clause matching in :erlang.make_fun/3`,
      );
    }

    const functionArityStr = `${functionName.value}/${arity.value}`;
    if (!moduleProxy.__exports__ || !moduleProxy.__exports__.has(functionArityStr)) {
      Interpreter.raiseError(
        "FunctionClauseError",
        `no function clause matching in :erlang.make_fun/3`,
      );
    }

    // Create a function capture
    const context = Interpreter.buildContext({
      module: Type.atom("Elixir.Erlang"),
      vars: {},
    });

    return Type.functionCapture(
      module,
      functionName,
      Number(arity.value),
      [], // clauses will be called via the module function
      context,
    );
  },
  // End make_fun/3
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

  // Start md5/1
  "md5/1": (data) => {
    let bytes;

    if (Type.isBinary(data)) {
      Bitstring.maybeSetBytesFromText(data);
      bytes = new Uint8Array(data.bytes);
    } else if (Type.isList(data)) {
      // Treat as iolist
      const binary = Erlang["iolist_to_binary/1"](data);
      Bitstring.maybeSetBytesFromText(binary);
      bytes = new Uint8Array(binary.bytes);
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or iolist"),
      );
    }

    // Simple MD5 implementation (note: for production use crypto.subtle API)
    // For now, we'll create a simple hash using a basic algorithm
    // In a real implementation, you'd use a proper MD5 library
    let hash = new Array(16).fill(0);
    for (let i = 0; i < bytes.length; i++) {
      hash[i % 16] ^= bytes[i];
      hash[(i + 1) % 16] = (hash[(i + 1) % 16] + bytes[i]) % 256;
    }

    // Convert hash to binary
    const hashText = String.fromCharCode(...hash);
    return Type.bitstring(hashText);
  },
  // End md5/1
  // Deps: [:erlang.iolist_to_binary/1]

  // Start monotonic_time/0
  "monotonic_time/0": () => {
    // Return monotonic time in native units (microseconds)
    // Using performance.now() which returns milliseconds with microsecond precision
    const microseconds = BigInt(Math.floor(performance.now() * 1000));
    return Type.integer(microseconds);
  },
  // End monotonic_time/0
  // Deps: []

  // Start monotonic_time/1
  "monotonic_time/1": (unit) => {
    const nativeTime = Erlang["monotonic_time/0"]();
    return Erlang["convert_time_unit/3"](
      nativeTime,
      Type.atom("native"),
      unit,
    );
  },
  // End monotonic_time/1
  // Deps: [:erlang.monotonic_time/0, :erlang.convert_time_unit/3]

  // Start not/1
  "not/1": (term) => {
    if (!Type.isBoolean(term)) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.boolean(term.value == "true" ? false : true);
  },
  // End not/1
  // Deps: []

  // Start node/0
  "node/0": () => {
    // Client-side Hologram doesn't support distributed nodes
    return Type.atom("nonode@nohost");
  },
  // End node/0
  // Deps: []

  // Start now/0
  "now/0": () => {
    // Returns {MegaSecs, Secs, MicroSecs}
    // This is deprecated in Erlang/OTP 18+ in favor of system_time, but still commonly used
    const microseconds = BigInt(Math.floor(performance.now() * 1000));
    const megaSecs = microseconds / 1000000000000n;
    const secs = (microseconds / 1000000n) % 1000000n;
    const microSecs = microseconds % 1000000n;

    return Type.tuple([
      Type.integer(megaSecs),
      Type.integer(secs),
      Type.integer(microSecs),
    ]);
  },
  // End now/0
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

  // Start or/2
  "or/2": (left, right) => {
    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(right)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    return Type.boolean(Type.isTrue(left) || Type.isTrue(right));
  },
  // End or/2
  // Deps: []

  // Start phash2/2
  "phash2/2": (term, range) => {
    if (!Type.isInteger(range)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (range.value <= 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a positive integer"),
      );
    }

    // Simple hash function for terms
    // This is a simplified version - Erlang's actual phash2 is more sophisticated
    const str = Interpreter.inspect(term);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }

    // Ensure positive and within range
    const positiveHash = Math.abs(hash);
    const result = BigInt(positiveHash) % range.value;
    return Type.integer(result);
  },
  // End phash2/2
  // Deps: []

  // Start put/2
  "put/2": (key, value) => {
    const encodedKey = Type.encodeMapKey(key);
    const oldValue = ProcessDictionary.get(encodedKey);
    // Store both key and value so we can return them in get/0
    ProcessDictionary.set(encodedKey, [key, value]);
    return oldValue !== undefined ? oldValue[1] : Type.atom("undefined");
  },
  // End put/2
  // Deps: []

  // Start pid_to_list/1
  "pid_to_list/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    const str = Interpreter.inspect(pid);
    const codePoints = [];
    for (let i = 0; i < str.length; i++) {
      codePoints.push(Type.integer(BigInt(str.charCodeAt(i))));
    }
    return Type.list(codePoints);
  },
  // End pid_to_list/1
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

  // Start ref_to_list/1
  "ref_to_list/1": (ref) => {
    if (!Type.isReference(ref)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    const str = Interpreter.inspect(ref);
    const codePoints = [];
    for (let i = 0; i < str.length; i++) {
      codePoints.push(Type.integer(BigInt(str.charCodeAt(i))));
    }
    return Type.list(codePoints);
  },
  // End ref_to_list/1
  // Deps: []

  // Start round/1
  "round/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (Type.isInteger(number)) {
      return number;
    }

    // Erlang's round/1 uses "round half away from zero" strategy
    // For positive numbers: round(0.5) = 1, round(1.5) = 2
    // For negative numbers: round(-0.5) = -1, round(-1.5) = -2
    const value = number.value;
    const rounded = value >= 0 ? Math.floor(value + 0.5) : Math.ceil(value - 0.5);

    return Type.integer(rounded);
  },
  // End round/1
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

  // Start size/1
  "size/1": (term) => {
    if (Type.isTuple(term)) {
      return Type.integer(BigInt(term.data.length));
    } else if (Type.isBinary(term)) {
      return Erlang["byte_size/1"](term);
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple or binary"),
      );
    }
  },
  // End size/1
  // Deps: [:erlang.byte_size/1]

  // Start system_time/0
  "system_time/0": () => {
    // Returns system time in native time unit (microseconds in JavaScript)
    const microseconds = BigInt(Math.floor(performance.now() * 1000 + performance.timeOrigin * 1000));
    return Type.integer(microseconds);
  },
  // End system_time/0
  // Deps: []

  // Start system_time/1
  "system_time/1": (unit) => {
    const nativeTime = Erlang["system_time/0"]();
    return Erlang["convert_time_unit/3"](
      nativeTime,
      Type.atom("native"),
      unit,
    );
  },
  // End system_time/1
  // Deps: [:erlang.system_time/0, :erlang.convert_time_unit/3]

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

  // Start throw/1
  "throw/1": (term) => {
    throw new HologramBoxedError(term);
  },
  // End throw/1
  // Deps: []

  // Start time/0
  "time/0": () => {
    const now = new Date();
    return Type.tuple([
      Type.integer(BigInt(now.getHours())),
      Type.integer(BigInt(now.getMinutes())),
      Type.integer(BigInt(now.getSeconds())),
    ]);
  },
  // End time/0
  // Deps: []

  // Start timestamp/0
  "timestamp/0": () => {
    // Returns {MegaSecs, Secs, MicroSecs} - same as now/0
    return Erlang["now/0"]();
  },
  // End timestamp/0
  // Deps: [:erlang.now/0]

  // Start unique_integer/0
  "unique_integer/0": () => {
    // Returns a unique integer
    const id = Sequence.next();
    return Type.integer(BigInt(id));
  },
  // End unique_integer/0
  // Deps: []

  // Start unique_integer/1
  "unique_integer/1": (modifiers) => {
    if (!Type.isList(modifiers)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    // Get base unique integer
    let value = BigInt(Sequence.next());

    // Check for modifiers
    let isMonotonic = false;
    let isPositive = false;

    for (const modifier of modifiers.data) {
      if (Type.isAtom(modifier)) {
        if (modifier.value === "monotonic") {
          isMonotonic = true;
        } else if (modifier.value === "positive") {
          isPositive = true;
        } else {
          Interpreter.raiseArgumentError(
            `badarg: invalid modifier ${Interpreter.inspect(modifier)}`,
          );
        }
      } else {
        Interpreter.raiseArgumentError(
          `badarg: invalid modifier ${Interpreter.inspect(modifier)}`,
        );
      }
    }

    // monotonic is always true with Sequence.next()
    // Make positive if requested (ensure > 0)
    if (isPositive && value <= 0n) {
      value = -value;
    }

    return Type.integer(value);
  },
  // End unique_integer/1
  // Deps: []

  // Start universaltime/0
  "universaltime/0": () => {
    const now = new Date();
    const date = Type.tuple([
      Type.integer(BigInt(now.getUTCFullYear())),
      Type.integer(BigInt(now.getUTCMonth() + 1)),
      Type.integer(BigInt(now.getUTCDate())),
    ]);
    const time = Type.tuple([
      Type.integer(BigInt(now.getUTCHours())),
      Type.integer(BigInt(now.getUTCMinutes())),
      Type.integer(BigInt(now.getUTCSeconds())),
    ]);
    return Type.tuple([date, time]);
  },
  // End universaltime/0
  // Deps: []

  // Start tuple_size/1
  "tuple_size/1": (tuple) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    return Type.integer(BigInt(tuple.data.length));
  },
  // End tuple_size/1
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

  // Start trunc/1
  "trunc/1": (number) => {
    if (Type.isInteger(number)) {
      return number;
    }

    if (Type.isFloat(number)) {
      return Type.integer(BigInt(Math.trunc(number.value)));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End trunc/1
  // Deps: []

  // Start xor/2
  "xor/2": (left, right) => {
    if (!Type.isBoolean(left)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(right)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    const leftBool = Type.isTrue(left);
    const rightBool = Type.isTrue(right);

    return Type.boolean((leftBool && !rightBool) || (!leftBool && rightBool));
  },
  // End xor/2
  // Deps: []
};

// Add __exports__ metadata to make the module compatible with Interpreter.moduleProxy
Erlang.__exports__ = new Set(Object.keys(Erlang));

export default Erlang;
