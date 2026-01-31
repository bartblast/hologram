"use strict";

import Bitstring from "../bitstring.mjs";
import ERTS from "../erts.mjs";
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
  // Start _validate_time_unit/2
  "_validate_time_unit/2": (unit, argumentIndex) => {
    const validAtomUnits = [
      "nanosecond",
      "nano_seconds",
      "microsecond",
      "micro_seconds",
      "millisecond",
      "milli_seconds",
      "second",
      "seconds",
      "native",
      "perf_counter",
    ];

    if (
      !(Type.isAtom(unit) && validAtomUnits.includes(unit.value)) &&
      !(Type.isInteger(unit) && unit.value > 0n)
    ) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(argumentIndex, "invalid time unit"),
      );
    }
  },
  // End _validate_time_unit/2
  // Deps: []

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

  // Start apply/2
  "apply/2": (fun, args) => {
    if (!Type.isAnonymousFunction(fun)) {
      Interpreter.raiseBadFunctionError(fun);
    }

    if (!Type.isProperList(args)) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Interpreter.callAnonymousFunction(fun, args.data);
  },
  // End apply/2
  // Deps: []

  // :erlang.apply/3 calls are encoded as Interpreter.callNamedFuntion() calls.
  // See: https://github.com/bartblast/hologram/blob/4e832c722af7b0c1a0cca1c8c08287b999ecae78/lib/hologram/compiler/encoder.ex#L559
  // Start apply/3
  "apply/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        `you attempted to apply a function named ${Interpreter.inspect(fun)} on ${Interpreter.inspect(module)}. If you are using Kernel.apply/3, make sure the module is an atom. If you are using the dot syntax, such as module.function(), make sure the left-hand side of the dot is an atom representing a module`,
      );
    }

    if (!Type.isAtom(fun)) {
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

    const context = Interpreter.buildContext({module: Type.nil()});

    return Interpreter.callNamedFunction(module, fun, args, context);
  },
  // End apply/3
  // Deps: []

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

  // Start band/2
  "band/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArithmeticError(`Bitwise.band(${arg1}, ${arg2})`);
    }

    return Type.integer(integer1.value & integer2.value);
  },
  // End band/2
  // Deps: []

  // Start binary_part/3
  "binary_part/3": (subject, start, length) => {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(start)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(length)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    const totalBytes = Bitstring.calculateBitCount(subject) / 8;

    if (start.value < 0n || start.value > totalBytes) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    const isReverse = length.value < 0n;

    const outOfRangeForward =
      !isReverse && start.value + length.value > totalBytes;

    const outOfRangeReverse = isReverse && start.value + length.value < 0n;

    if (outOfRangeForward || outOfRangeReverse) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "out of range"),
      );
    }

    const actualStart = isReverse ? start.value + length.value : start.value;
    const actualLength = isReverse ? -length.value : length.value;

    return Bitstring.takeChunk(
      subject,
      Number(actualStart) * 8,
      Number(actualLength) * 8,
    );
  },
  // End binary_part/3

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

  // Start binary_to_float/1
  "binary_to_float/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    const text = Bitstring.toText(binary);

    const floatRegex = /^[+-]?\d+\.\d+([eE][+-]?\d+)?$/;

    if (!floatRegex.test(text)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    }

    return Type.float(Number(text));
  },
  // End binary_to_float/1
  // Deps: []

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

  // Start binary_to_list/1
  "binary_to_list/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);

    return Type.list(Array.from(binary.bytes).map((b) => Type.integer(b)));
  },
  // End binary_to_list/1
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

  // Start bor/2
  "bor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArithmeticError(`Bitwise.bor(${arg1}, ${arg2})`);
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

      Interpreter.raiseArithmeticError(`Bitwise.bsl(${arg1}, ${arg2})`);
    }

    const integerValue = integer.value;
    const shiftValue = shift.value;

    if (shiftValue < 0n) {
      // Erlang's bsl with negative shift is equivalent to bsr with positive shift
      return Type.integer(integerValue >> -shiftValue);
    } else {
      return Type.integer(integerValue << shiftValue);
    }
  },
  // End bsl/2
  // Deps: []

  // Start bsr/2
  "bsr/2": (integer, shift) => {
    if (!Type.isInteger(integer) || !Type.isInteger(shift)) {
      const arg1 = Interpreter.inspect(integer);
      const arg2 = Interpreter.inspect(shift);

      Interpreter.raiseArithmeticError(`Bitwise.bsr(${arg1}, ${arg2})`);
    }

    const integerValue = integer.value;
    const shiftValue = shift.value;

    if (shiftValue < 0n) {
      // Erlang's bsr with negative shift is equivalent to bsl with positive shift
      return Type.integer(integerValue << -shiftValue);
    } else {
      return Type.integer(integerValue >> shiftValue);
    }
  },
  // End bsr/2
  // Deps: []

  // Start bxor/2
  "bxor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1) || !Type.isInteger(integer2)) {
      const arg1 = Interpreter.inspect(integer1);
      const arg2 = Interpreter.inspect(integer2);

      Interpreter.raiseArithmeticError(`Bitwise.bxor(${arg1}, ${arg2})`);
    }

    return Type.integer(integer1.value ^ integer2.value);
  },
  // End bxor/2
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

  // Start convert_time_unit/3
  "convert_time_unit/3": (time, fromUnit, toUnit) => {
    // :native and :perf_counter are technically platform-dependent in Erlang/OTP,
    // but in practice they're nanoseconds on all major platforms (Linux, macOS, Windows).
    // We standardize on nanoseconds to match typical Erlang behavior while keeping
    // JS behavior predictable.
    const NATIVE_TIME_UNIT = 1_000_000_000n;
    const PERF_COUNTER_TIME_UNIT = 1_000_000_000n;

    const resolveTimeUnit = (unit) => {
      switch (unit.value) {
        case "nanosecond":
        case "nano_seconds":
          return 1_000_000_000n;

        case "microsecond":
        case "micro_seconds":
          return 1_000_000n;

        case "millisecond":
        case "milli_seconds":
          return 1_000n;

        case "second":
        case "seconds":
          return 1n;

        case "native":
          return NATIVE_TIME_UNIT;

        case "perf_counter":
          return PERF_COUNTER_TIME_UNIT;

        // integer
        default:
          return unit.value;
      }
    };

    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    Erlang["_validate_time_unit/2"](fromUnit, 2);
    Erlang["_validate_time_unit/2"](toUnit, 3);

    const fromUnitValue = resolveTimeUnit(fromUnit);
    const toUnitValue = resolveTimeUnit(toUnit);
    const numerator = toUnitValue * time.value;

    const adjustedNumerator =
      time.value < 0n ? numerator - (fromUnitValue - 1n) : numerator;

    const result = adjustedNumerator / fromUnitValue;

    return Type.integer(result);
  },
  // End convert_time_unit/3
  // Deps: [:erlang._validate_time_unit/2]

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

    if (index.value > tuple.data.length || index.value < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    const data = tuple.data.toSpliced(Number(index.value) - 1, 1);

    return Type.tuple(data);
  },
  // End delete_element/2
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

  // Start float/1
  "float/1": (number) => {
    if (Type.isInteger(number)) {
      return Type.float(Number(number.value));
    } else if (Type.isFloat(number)) {
      return number;
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End float/1
  // Deps: []

  // Start float_to_list/2
  "float_to_list/2": (float, opts) => {
    const binary = Erlang["float_to_binary/2"](float, opts);

    return Bitstring.toCodepoints(binary);
  },
  // End float_to_list/2
  // Deps: [:erlang.float_to_binary/2]

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

    const SHORT_EXPONENTIAL_THRESHOLD = 9_007_199_254_740_992.0; // 2^53 - Erlang always uses exponential notation at this boundary
    const JS_PRECISION_LIMIT = 100; // Max precision for toFixed() and toExponential()
    const ERLANG_BUFFER_LIMIT = 256;
    const ERLANG_DEFAULT_SCIENTIFIC = 20;
    const FIXED_PRECISION_FOR_NEGATIVE = 6;

    let decimals = null;
    let scientific = ERLANG_DEFAULT_SCIENTIFIC;
    let isCompact = false;
    let isShort = false;
    let lastOpt = null;

    // Parse options
    for (const opt of opts.data) {
      if (Interpreter.isStrictlyEqual(opt, Type.atom("short"))) {
        isShort = true;
        lastOpt = "short";
        continue;
      }

      if (Interpreter.isStrictlyEqual(opt, Type.atom("compact"))) {
        isCompact = true;
        continue;
      }

      if (!Type.isTuple(opt) || opt.data.length !== 2) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "invalid option in list"),
        );
      }

      const [key, value] = opt.data;

      if (
        Interpreter.isStrictlyEqual(key, Type.atom("decimals")) &&
        Type.isInteger(value) &&
        value.value >= 0n &&
        value.value <= 253n
      ) {
        decimals = Number(value.value);
        lastOpt = "decimals";
      } else if (
        Interpreter.isStrictlyEqual(key, Type.atom("scientific")) &&
        Type.isInteger(value) &&
        value.value <= 249n
      ) {
        scientific = Number(value.value);
        lastOpt = "scientific";
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "invalid option in list"),
        );
      }
    }

    // Only keep the last formatting option, reset others to defaults
    if (lastOpt === "short") {
      decimals = null;
      scientific = ERLANG_DEFAULT_SCIENTIFIC;
    } else if (lastOpt === "decimals") {
      isShort = false;
      scientific = ERLANG_DEFAULT_SCIENTIFIC;
    } else if (lastOpt === "scientific") {
      isShort = false;
      decimals = null;
    }

    // Check if we have negative zero (JavaScript preserves signed zero)
    const isNegativeZero = Object.is(float.value, -0);

    let result;

    if (isShort) {
      const absVal = Math.abs(float.value);

      if (absVal >= SHORT_EXPONENTIAL_THRESHOLD) {
        // For values >= 2^53, always use exponential notation per Erlang spec
        result = float.value.toExponential();
      } else {
        // For values < 2^53, compare character counts of decimal vs exponential
        // and choose the shorter representation (decimal wins ties per Erlang spec)

        let decimalResult = float.value.toString();

        // Ensure decimal point exists for proper float format
        if (decimalResult === "0") {
          decimalResult = "0.0";
        } else if (
          absVal >= 1 &&
          !decimalResult.includes(".") &&
          !decimalResult.includes("e")
        ) {
          decimalResult += ".0";
        }

        let expResult = float.value.toExponential();

        // Ensure mantissa has at least one decimal digit (e.g., "9e-4" → "9.0e-4")
        if (!expResult.includes(".")) {
          expResult = expResult.replace(/e/, ".0e");
        }

        // Choose the representation with fewer characters (decimal wins ties)
        result =
          expResult.length < decimalResult.length ? expResult : decimalResult;
      }

      // Format exponent: remove + sign (e.g., e+15 → e15), keep - sign as-is
      if (result.includes("e")) {
        result = result.replace(/e\+/, "e");
      }
    } else if (decimals !== null) {
      // JavaScript's toFixed() has a limit of 100, but Erlang allows up to 253.
      // For values > 100, we use toFixed(100) and manually pad with zeros.
      if (decimals > JS_PRECISION_LIMIT) {
        result = float.value.toFixed(JS_PRECISION_LIMIT);
        const additionalZeros = decimals - JS_PRECISION_LIMIT;
        result = result + "0".repeat(additionalZeros);
      } else {
        result = float.value.toFixed(decimals);
      }

      if (isCompact && decimals > 0) {
        result = result.replace(/0+$/, "").replace(/\.$/, ".0");
      }
    } else {
      // For negative scientific, Erlang uses fixed precision of 6 decimal places
      const precision =
        scientific < 0 ? FIXED_PRECISION_FOR_NEGATIVE : scientific;

      // JavaScript's toExponential() has a limit of 100, but Erlang allows up to 249.
      // For values > 100, we use toExponential(100) and manually pad with zeros.
      if (precision > JS_PRECISION_LIMIT) {
        result = float.value.toExponential(JS_PRECISION_LIMIT);
        const [mantissa, exponent] = result.split("e");
        const currentDigits = mantissa.split(".")[1].length;
        const additionalZeros = precision - currentDigits;
        result = mantissa + "0".repeat(additionalZeros) + "e" + exponent;
      } else {
        result = float.value.toExponential(precision);
      }

      // Erlang format uses zero-padded exponents (e.g., e+00, e-04)
      result = result.replace(/e([+-])(\d)$/, "e$10$2");
    }

    // Preserve negative zero sign if needed
    // JavaScript's toString/toFixed/toExponential lose the sign of -0, so we restore it
    if (isNegativeZero && !result.startsWith("-")) {
      result = "-" + result;
    }

    // Erlang enforces a 256-byte buffer limit for the result
    if (result.length >= ERLANG_BUFFER_LIMIT) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "invalid option in list"),
      );
    }

    return Type.bitstring(result);
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

  // Start insert_element/3
  "insert_element/3": (index, tuple, value) => {
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

    if (index.value <= 0n || index.value > tuple.data.length + 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    // The tuple index is one-based, so we need to compensate
    const data = tuple.data.toSpliced(Number(index.value) - 1, 0, value);
    return Type.tuple(data);
  },
  // End insert_element/3
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

    if (!Type.isInteger(base) || base.value < 2n || base.value > 36n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    }

    const text = integer.value.toString(Number(base.value)).toUpperCase();

    return Bitstring.toCodepoints(Type.bitstring(text));
  },
  // End integer_to_list/2
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

  // Start is_map_key/2
  "is_map_key/2": (key, map) => {
    return Erlang_Maps["is_key/2"](key, map);
  },
  // End is_map_key/2
  // Deps: [:maps.is_key/2]

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

  // Start list_to_integer/1
  "list_to_integer/1": (list) => {
    return Erlang["list_to_integer/2"](list, Type.integer(10n));
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

    if (!Type.isInteger(base) || base.value < 2n || base.value > 36n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          2,
          "not an integer in the range 2 through 36",
        ),
      );
    }

    if (list.data.length === 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of an integer",
        ),
      );
    }

    const codes = [];

    // TODO: consider - use isCharlist() helper instead when it's implemented
    for (const code of list.data) {
      if (!Type.isInteger(code)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not a textual representation of an integer",
          ),
        );
      }

      codes.push(Number(code.value));
    }

    const str = String.fromCharCode(...codes);
    const baseNum = Number(base.value);
    const strLower = str.toLowerCase();
    let validPattern;

    if (baseNum <= 10) {
      const maxDigit = baseNum - 1;
      validPattern = new RegExp(`^[+-]?[0-${maxDigit}]+$`);
    } else {
      const maxLetter = String.fromCharCode(97 + baseNum - 11);
      validPattern = new RegExp(`^[+-]?[0-9a-${maxLetter}]+$`);
    }

    if (!validPattern.test(strLower)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of an integer",
        ),
      );
    }

    // Parse the string to BigInt manually to avoid precision loss with parseInt
    const bigBase = BigInt(baseNum);
    let result = 0n;
    let sign = 1n;
    let startIndex = 0;

    if (strLower[0] === "-") {
      sign = -1n;
      startIndex = 1;
    } else if (strLower[0] === "+") {
      startIndex = 1;
    }

    for (let i = startIndex; i < strLower.length; i++) {
      const char = strLower[i];

      const digitValue =
        char >= "0" && char <= "9"
          ? BigInt(char.charCodeAt(0) - 48) // '0' is 48, so '0' becomes 0
          : BigInt(char.charCodeAt(0) - 87); // 'a' is 97, so 'a' becomes 10

      result = result * bigBase + digitValue;
    }

    return Type.integer(sign * result);
  },
  // End list_to_integer/2
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

  // Start list_to_ref/1
  "list_to_ref/1": (codePoints) => {
    if (!Type.isProperList(codePoints)) {
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
          "not a textual representation of a reference",
        ),
      );
    }

    const segments = codePoints.data.map((codePoint) =>
      Type.bitstringSegment(codePoint, {type: "utf8"}),
    );

    const regex = /^#Ref<([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)>$/;
    const matches = Bitstring.toText(Type.bitstring(segments)).match(regex);

    if (matches === null) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a reference",
        ),
      );
    }

    const localIncarnationId = Number(matches[1]);

    // The idWords in the string representation are in reversed order
    const idWords = [
      Number(matches[4]),
      Number(matches[3]),
      Number(matches[2]),
    ];

    const refInfo = ERTS.nodeTable.getNodeAndCreation(localIncarnationId);

    if (refInfo === null) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a reference",
        ),
      );
    }

    return Type.reference(refInfo.node, refInfo.creation, idWords);
  },
  // End list_to_ref/1
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

  // Start localtime/0
  "localtime/0": () => {
    const now = new Date();

    const year = now.getFullYear();
    const month = now.getMonth() + 1; // JavaScript months are 0-indexed
    const day = now.getDate();

    const hour = now.getHours();
    const minute = now.getMinutes();
    const second = now.getSeconds();

    const date = Type.tuple([
      Type.integer(year),
      Type.integer(month),
      Type.integer(day),
    ]);

    const time = Type.tuple([
      Type.integer(hour),
      Type.integer(minute),
      Type.integer(second),
    ]);

    return Type.tuple([date, time]);
  },
  // End localtime/0
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
        Interpreter.buildArgumentErrorMsg(3, "out of range"),
      );
    }

    if (arity.value > 255n) {
      Interpreter.raiseArgumentError("argument error");
    }

    const arityValue = Number(arity.value);
    const functionNameText = functionName.value;

    const paramNames = Array.from(
      {length: arityValue},
      (_elem, index) => `$${index + 1}`,
    );

    const clauses = [
      {
        params: (_context) =>
          paramNames.map((name) => Type.variablePattern(name)),
        guards: [],
        body: (context) => {
          const args = Type.list(paramNames.map((name) => context.vars[name]));

          return Interpreter.callNamedFunction(
            module,
            functionName,
            args,
            context,
          );
        },
      },
    ];

    const capturedModule = module.value.startsWith("Elixir.")
      ? Interpreter.moduleExName(module)
      : `:${module.value}`;

    const context = Interpreter.buildContext({module: Type.nil()});

    return Type.functionCapture(
      capturedModule,
      functionNameText,
      arityValue,
      clauses,
      context,
    );
  },
  // End make_fun/3
  // Deps: []

  // Start make_ref/0
  "make_ref/0": () => {
    const node = ERTS.nodeTable.CLIENT_NODE;
    const creation = 0;

    // TODO: implement ID words similarly to how it's done in Erlang
    const idWords = [
      Utils.randomUint32(),
      Utils.randomUint32(),
      ERTS.referenceSequence.next(),
    ];

    return Type.reference(node, creation, idWords);
  },
  // End make_ref/0
  // Deps: []

  // Start make_tuple/2
  "make_tuple/2": (arity, value) => {
    // The Erlang implementation says that the index is out of range even when it is not an integer
    if (!Type.isInteger(arity) || arity.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    const data = Array(Number(arity.value)).fill(value);

    return Type.tuple(data);
  },
  // End make_tuple/2
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

  // Start monotonic_time/0
  "monotonic_time/0": () => {
    // performance.now() returns milliseconds with sub-ms precision.
    // We convert to nanoseconds (multiply by 1_000_000).
    //
    // MAX_SAFE_INTEGER == 9_007_199_254_740_991
    // MAX_SAFE_INTEGER / 1_000_000 ≈ 9_007_199_254 ms ≈ 104 days.
    // Beyond that, ms * 1_000_000 exceeds MAX_SAFE_INTEGER and loses precision.
    //
    // Fast path: direct multiplication when safely within bounds.
    // Safe path: split whole/fractional parts to avoid large float multiplication.
    const ms = performance.now();

    if (ms < 9_007_199_254) {
      return Type.integer(BigInt(Math.round(ms * 1_000_000)));
    }

    const msWhole = Math.trunc(ms);

    return Type.integer(
      BigInt(msWhole) * 1_000_000n +
        BigInt(Math.round((ms - msWhole) * 1_000_000)),
    );
  },
  // End monotonic_time/0
  // Deps: []

  // Start monotonic_time/1
  "monotonic_time/1": (unit) => {
    // TODO: unit is validated twice - here (for correct arg index in error message)
    // and in convert_time_unit/3. This could be optimized in the future.
    Erlang["_validate_time_unit/2"](unit, 1);
    const nativeTime = Erlang["monotonic_time/0"]();

    return Erlang["convert_time_unit/3"](nativeTime, Type.atom("native"), unit);
  },
  // End monotonic_time/1
  // Deps: [:erlang._validate_time_unit/2, :erlang.convert_time_unit/3, :erlang.monotonic_time/0]

  // Start node/0
  "node/0": () => {
    return Type.atom(ERTS.nodeTable.CLIENT_NODE);
  },
  // End node/0
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

  // Start pid_to_list/1
  "pid_to_list/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    const pidText = `<${pid.segments.join(".")}>`;

    return Bitstring.toCodepoints(Type.bitstring(pidText));
  },
  // End pid_to_list/1
  // Deps: []

  // Start ref_to_list/1
  "ref_to_list/1": (reference) => {
    if (!Type.isReference(reference)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    const localIncarnationId = ERTS.nodeTable.getLocalIncarnationId(
      reference.node,
      reference.creation,
    );

    return Type.charlist(
      `#Ref<${localIncarnationId}.${reference.idWords.toReversed().join(".")}>`,
    );
  },
  // End ref_to_list/1
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

  // Start setelement/3
  "setelement/3": (index, tuple, value) => {
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

    if (index.value <= 0n || index.value > tuple.data.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    const data = [...tuple.data];
    // The tuple index is one-based, so we need to compensate
    data[Number(index.value) - 1] = value;

    return Type.tuple(data);
  },
  // End setelement/3
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

  // Start time_offset/0
  "time_offset/0": () => {
    return Erlang["time_offset/1"](Type.atom("native"));
  },
  // End time_offset/0
  // Deps: [:erlang.time_offset/1]

  // Start time_offset/1
  "time_offset/1": (unit) => {
    const systemTimeNs = BigInt(Date.now()) * 1_000_000n;
    const monoTimeNs = BigInt(Math.round(performance.now() * 1_000_000));
    const offsetNs = systemTimeNs - monoTimeNs;

    return Erlang["convert_time_unit/3"](
      Type.integer(offsetNs),
      Type.atom("native"),
      unit,
    );
  },
  // End time_offset/1
  // Deps: [:erlang.convert_time_unit/3]

  // Start trunc/1
  "trunc/1": (number) => {
    if (!Type.isNumber(number)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a number"),
      );
    }

    if (Type.isFloat(number)) {
      // Erlang :erlang.trunc/1 converts -0 to 0 while JavaScript Math.trunc() does not
      return Type.integer(Math.trunc(number.value) + 0);
    }

    return number;
  },
  // End trunc/1
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

  // Start unique_integer/0
  "unique_integer/0": () => {
    return Type.integer(ERTS.uniqueIntegerSequence.next());
  },
  // End unique_integer/0
  // Deps: []

  // Start unique_integer/1
  // Simplified: always returns monotonic, positive integers regardless of modifiers.
  "unique_integer/1": (modifierList) => {
    if (!Type.isList(modifierList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isProperList(modifierList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    const validModifiers = ["monotonic", "positive"];

    for (const modifier of modifierList.data) {
      if (!Type.isAtom(modifier) || !validModifiers.includes(modifier.value)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "invalid modifier"),
        );
      }
    }

    return Erlang["unique_integer/0"]();
  },
  // End unique_integer/1
  // Deps: [:erlang.unique_integer/0]

  // Start xor/2
  "xor/2": (left, right) => {
    if (!Type.isBoolean(left) || !Type.isBoolean(right)) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.boolean(left.value != right.value);
  },
  // End xor/2
  // Deps: []
};

export default Erlang;
