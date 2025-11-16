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

  // Start append_element/2
  "append_element/2": (tuple, element) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    return Type.tuple([...tuple.data, element]);
  },
  // End append_element/2
  // Deps: []

  // Start apply/2
  "apply/2": (fun, args) => {
    if (!Type.isFunction(fun)) {
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

    // Call the function with the arguments
    return fun.fun(...args.data);
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

    // Get the module and function
    const moduleName = module.value;
    const funName = functionName.value;
    const arity = args.data.length;
    const key = `${funName}/${arity}`;

    // Check if the module and function exist
    if (!(moduleName in globalThis)) {
      Interpreter.raiseArgumentError(
        `module ${moduleName} is not loaded`,
      );
    }

    if (!(key in globalThis[moduleName])) {
      Interpreter.raiseArgumentError(
        `function ${moduleName}.${key} is undefined or private`,
      );
    }

    // Call the function
    return globalThis[moduleName][key](...args.data);
  },
  // End apply/3
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

  // Start binary_to_float/1
  "binary_to_float/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const text = Bitstring.toText(binary);
    const floatValue = parseFloat(text);

    if (isNaN(floatValue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a textual representation of a float"),
      );
    }

    return Type.float(floatValue);
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

  // Start binary_part/3
  "binary_part/3": (binary, start, length) => {
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

    if (!Type.isInteger(length)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    const startNum = Number(start.value);
    const lengthNum = Number(length.value);

    Bitstring.maybeSetBytesFromText(binary);
    const totalBytes = binary.bytes.length;

    if (startNum < 0 || lengthNum < 0 || startNum + lengthNum > totalBytes) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    return Bitstring.takeChunk(binary, startNum * 8, lengthNum * 8);
  },
  // End binary_part/3
  // Deps: []

  // Start binary_to_list/1
  "binary_to_list/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    return Type.list(
      Array.from(binary.bytes).map((byte) => Type.integer(byte)),
    );
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
    const totalBytes = binary.bytes.length;
    const startNum = Number(start.value);
    const stopNum = Number(stop.value);

    // Erlang uses 1-based indexing
    if (startNum < 1 || stopNum < 1 || startNum > stopNum || stopNum > totalBytes) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    // Convert to 0-based indexing for JavaScript
    const bytes = Array.from(binary.bytes).slice(startNum - 1, stopNum);
    return Type.list(bytes.map((byte) => Type.integer(byte)));
  },
  // End binary_to_list/3
  // Deps: []

  // Start binary_to_term/1
  "binary_to_term/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    // ETF (External Term Format) deserialization is complex
    // This would require a full implementation of Erlang's term encoding
    throw new HologramInterpreterError(
      "Function :erlang.binary_to_term/1 is not yet fully implemented in Hologram.\n" +
      "Deserializing Erlang External Term Format requires complex binary parsing.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End binary_to_term/1
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

  // Start bitstring_to_list/1
  "bitstring_to_list/1": (bitstring) => {
    if (!Type.isBitstring(bitstring)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    Bitstring.maybeSetBytesFromText(bitstring);
    const bitCount = Bitstring.calculateBitCount(bitstring);

    // If not byte-aligned, raise error
    if (bitCount % 8 !== 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    return Type.list(
      Array.from(bitstring.bytes).map((byte) => Type.integer(byte)),
    );
  },
  // End bitstring_to_list/1
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
    if (Type.isInteger(number)) {
      return number;
    } else if (Type.isFloat(number)) {
      return Type.integer(BigInt(Math.ceil(number.value)));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
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

    const idx = Number(index.value);
    if (idx < 1 || idx > tuple.data.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    const newData = tuple.data.filter((_, i) => i !== idx - 1);
    return Type.tuple(newData);
  },
  // End delete_element/2
  // Deps: []

  // Start date/0
  "date/0": () => {
    // Return current date as {Year, Month, Day}
    const now = new Date();
    return Type.tuple([
      Type.integer(BigInt(now.getFullYear())),
      Type.integer(BigInt(now.getMonth() + 1)), // JavaScript months are 0-indexed
      Type.integer(BigInt(now.getDate())),
    ]);
  },
  // End date/0
  // Deps: []

  // Start display/1
  "display/1": (term) => {
    console.log(Interpreter.inspect(term));
    return Type.atom("ok");
  },
  // End display/1
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

  // Start erase/0
  "erase/0": () => {
    // Clear all entries from process dictionary and return them
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    const entries = Array.from(globalThis.__hologramProcessDict.entries()).map(
      ([key, value]) => Type.tuple([JSON.parse(key), value])
    );

    globalThis.__hologramProcessDict.clear();
    return Type.list(entries);
  },
  // End erase/0
  // Deps: []

  // Start erase/1
  "erase/1": (key) => {
    // Erase key from process dictionary and return previous value
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    const encodedKey = Type.encodeMapKey(key);
    const prevValue = globalThis.__hologramProcessDict.get(encodedKey);
    globalThis.__hologramProcessDict.delete(encodedKey);

    return prevValue !== undefined ? prevValue : Type.atom("undefined");
  },
  // End erase/1
  // Deps: []

  // Start exit/1
  "exit/1": (reason) => {
    // Exit the current process with the given reason
    // In Hologram, this throws an error to simulate process exit
    throw new HologramBoxedError(
      Type.tuple([Type.atom("exit"), reason])
    );
  },
  // End exit/1
  // Deps: []

  // Start float/1
  "float/1": (number) => {
    if (Type.isFloat(number)) {
      return number;
    } else if (Type.isInteger(number)) {
      return Type.float(Number(number.value));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End float/1
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

  // Start float_to_list/1
  "float_to_list/1": (float) => {
    if (!Type.isFloat(float)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    }

    // Convert float to string, then to list of character codes
    const str = float.value.toString();
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End float_to_list/1
  // Deps: []

  // Start floor/1
  "floor/1": (number) => {
    if (Type.isInteger(number)) {
      return number;
    } else if (Type.isFloat(number)) {
      return Type.integer(BigInt(Math.floor(number.value)));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End floor/1
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

    const moduleName = module.value.startsWith("Elixir.")
      ? module.value
      : `Elixir.${module.value}`;
    const key = `${functionName.value}/${arity.value}`;

    // Check if module exists in globalThis
    if (!globalThis[moduleName]) {
      return Type.boolean(false);
    }

    // Check if function exists in the module
    return Type.boolean(key in globalThis[moduleName]);
  },
  // End function_exported/3
  // Deps: []

  // Start get/0
  "get/0": () => {
    // Get all key-value pairs from process dictionary
    // In Hologram, we simulate this with a global process dictionary
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    // Return as a list of {key, value} tuples
    const entries = Array.from(globalThis.__hologramProcessDict.entries()).map(
      ([key, value]) => Type.tuple([key, value])
    );
    return Type.list(entries);
  },
  // End get/0
  // Deps: []

  // Start get/1
  "get/1": (key) => {
    // Get value from process dictionary by key
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    const encodedKey = Type.encodeMapKey(key);
    const value = globalThis.__hologramProcessDict.get(encodedKey);

    return value !== undefined ? value : Type.atom("undefined");
  },
  // End get/1
  // Deps: []

  // Start get_keys/0
  "get_keys/0": () => {
    // Get all keys from process dictionary
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    const keys = Array.from(globalThis.__hologramProcessDict.keys()).map(
      (encodedKey) => JSON.parse(encodedKey)
    );

    return Type.list(keys);
  },
  // End get_keys/0
  // Deps: []

  // Start get_keys/1
  "get_keys/1": (value) => {
    // Get all keys that have the specified value
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    const keys = [];
    for (const [encodedKey, storedValue] of globalThis.__hologramProcessDict.entries()) {
      if (Interpreter.isStrictlyEqual(storedValue, value)) {
        keys.push(JSON.parse(encodedKey));
      }
    }

    return Type.list(keys);
  },
  // End get_keys/1
  // Deps: []

  // Start group_leader/0
  "group_leader/0": () => {
    // Return the group leader process (simplified in Hologram)
    return Type.pid("<0.0.0>");
  },
  // End group_leader/0
  // Deps: []

  // Start halt/0
  "halt/0": () => {
    // Halt the system - in browser context, this would close/reload
    throw new HologramInterpreterError(
      "Function :erlang.halt/0 is not fully supported in Hologram.\n" +
      "Cannot halt the Erlang runtime in a browser environment.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End halt/0
  // Deps: []

  // Start halt/1
  "halt/1": (status) => {
    // Halt with exit status
    throw new HologramInterpreterError(
      "Function :erlang.halt/1 is not fully supported in Hologram.\n" +
      "Cannot halt the Erlang runtime in a browser environment.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End halt/1
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
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // Convert integer to string, then to list of character codes
    const str = integer.value.toString();
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End integer_to_list/1
  // Deps: []

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

    // Convert integer to string with base, then to list of character codes
    const str = integer.value.toString(baseNum).toUpperCase();
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End integer_to_list/2
  // Deps: []

  // Start insert_element/3
  "insert_element/3": (index, tuple, element) => {
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

    const idx = Number(index.value);
    // insert_element allows idx from 1 to length+1
    if (idx < 1 || idx > tuple.data.length + 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    const newData = [
      ...tuple.data.slice(0, idx - 1),
      element,
      ...tuple.data.slice(idx - 1),
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

  // Start iolist_to_list/1
  "iolist_to_list/1": (ioListOrBinary) => {
    // If it's a binary, convert to list of bytes
    if (Type.isBitstring(ioListOrBinary)) {
      Bitstring.maybeSetBytesFromText(ioListOrBinary);
      return Type.list(
        Array.from(ioListOrBinary.bytes).map((byte) => Type.integer(byte)),
      );
    }

    // If it's a list, flatten and convert all elements
    const flattened = Erlang_Lists["flatten/1"](ioListOrBinary);

    const bytes = flattened.data.flatMap((term) => {
      if (Type.isBitstring(term)) {
        Bitstring.maybeSetBytesFromText(term);
        return Array.from(term.bytes);
      } else if (Type.isInteger(term)) {
        const value = Number(term.value);
        if (value < 0 || value > 255) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(
              1,
              "not an iolist term",
            ),
          );
        }
        return [value];
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not an iolist term",
          ),
        );
      }
    });

    return Type.list(bytes.map((byte) => Type.integer(byte)));
  },
  // End iolist_to_list/1
  // Deps: [:lists.flatten/1]

  // Start iolist_size/1
  "iolist_size/1": (ioListOrBinary) => {
    // Convert to binary and get its size
    const binary = Erlang["iolist_to_binary/1"](ioListOrBinary);
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

  // Start is_map_key/2
  "is_map_key/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const encodedKey = Type.encodeMapKey(key);
    return Type.boolean(encodedKey in map.data);
  },
  // End is_map_key/2
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

  // Start list_to_port/1
  "list_to_port/1": (list) => {
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

    // Convert list of integers to string
    const str = String.fromCharCode(...list.data.map((i) => Number(i.value)));
    return Type.port(str);
  },
  // End list_to_port/1
  // Deps: []

  // Start list_to_reference/1
  "list_to_reference/1": (list) => {
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

    // Convert list of integers to string
    const str = String.fromCharCode(...list.data.map((i) => Number(i.value)));
    return Type.reference(str);
  },
  // End list_to_reference/1
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

    // Validate that all elements are integers representing valid codepoints
    const areCodePointsValid = list.data.every(
      (item) => Type.isInteger(item) && Bitstring.validateCodePoint(item.value),
    );

    if (!areCodePointsValid) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid list of codepoints"),
      );
    }

    // Convert codepoints to string
    const segments = list.data.map((codePoint) =>
      Type.bitstringSegment(codePoint, {type: "utf8"}),
    );
    const text = Bitstring.toText(Type.bitstring(segments));

    return Type.atom(text);
  },
  // End list_to_atom/1
  // Deps: []

  // Start list_to_existing_atom/1
  "list_to_existing_atom/1": (list) => {
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

    const segments = list.data.map((item) => {
      if (!Type.isInteger(item)) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not an integer"),
        );
      }
      return Type.bitstringSegment(item, {type: "integer", size: 8});
    });

    const text = Bitstring.toText(Type.bitstring(segments));

    // Check if atom exists (in real Erlang this checks the atom table)
    // In Hologram, we'll create it if it doesn't exist, but raise if invalid
    // This is a simplified implementation - true Erlang behavior would require atom table tracking
    return Type.atom(text);
  },
  // End list_to_existing_atom/1
  // Deps: []

  // Start list_to_binary/1
  "list_to_binary/1": (list) => {
    // list_to_binary is an alias for iolist_to_binary
    return Erlang["iolist_to_binary/1"](list);
  },
  // End list_to_binary/1
  // Deps: [:erlang.iolist_to_binary/1]

  // Start list_to_bitstring/1
  "list_to_bitstring/1": (list) => {
    // list_to_bitstring is an alias for iolist_to_binary
    return Erlang["iolist_to_binary/1"](list);
  },
  // End list_to_bitstring/1
  // Deps: [:erlang.iolist_to_binary/1]

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

    // Validate that all elements are integers representing valid codepoints
    const areCodePointsValid = list.data.every(
      (item) => Type.isInteger(item) && Bitstring.validateCodePoint(item.value),
    );

    if (!areCodePointsValid) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    }

    // Convert codepoints to string
    const segments = list.data.map((codePoint) =>
      Type.bitstringSegment(codePoint, {type: "utf8"}),
    );
    const text = Bitstring.toText(Type.bitstring(segments));

    // Validate float format and parse
    // Erlang requires floats to have a decimal point and at least one digit on each side
    const floatPattern = /^[+-]?\d+\.\d+([eE][+-]?\d+)?$/;
    if (!floatPattern.test(text)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    }

    const value = parseFloat(text);
    if (!isFinite(value)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of a float",
        ),
      );
    }

    return Type.float(value);
  },
  // End list_to_float/1
  // Deps: []

  // Start list_to_integer/1
  "list_to_integer/1": (list) => {
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

    // Validate that all elements are integers representing valid codepoints
    const areCodePointsValid = list.data.every(
      (item) => Type.isInteger(item) && Bitstring.validateCodePoint(item.value),
    );

    if (!areCodePointsValid) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of an integer",
        ),
      );
    }

    // Convert codepoints to string
    const segments = list.data.map((codePoint) =>
      Type.bitstringSegment(codePoint, {type: "utf8"}),
    );
    const text = Bitstring.toText(Type.bitstring(segments));

    // Validate integer format and parse
    const intPattern = /^[+-]?\d+$/;
    if (!intPattern.test(text)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a textual representation of an integer",
        ),
      );
    }

    return Type.integer(BigInt(text));
  },
  // End list_to_integer/1
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

  // Start localtime/0
  "localtime/0": () => {
    // Return local time as {{Year, Month, Day}, {Hour, Minute, Second}}
    const now = new Date();
    return Type.tuple([
      Type.tuple([
        Type.integer(BigInt(now.getFullYear())),
        Type.integer(BigInt(now.getMonth() + 1)),
        Type.integer(BigInt(now.getDate())),
      ]),
      Type.tuple([
        Type.integer(BigInt(now.getHours())),
        Type.integer(BigInt(now.getMinutes())),
        Type.integer(BigInt(now.getSeconds())),
      ]),
    ]);
  },
  // End localtime/0
  // Deps: []

  // Start make_ref/0
  "make_ref/0": () => {
    // Generate a unique reference using timestamp and random values
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 0xFFFFFFFF);
    const id = `#Ref<0.${timestamp}.${random}>`;
    return Type.reference(id);
  },
  // End make_ref/0
  // Deps: []

  // Start make_tuple/2
  "make_tuple/2": (size, initialValue) => {
    if (!Type.isInteger(size)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (size.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "negative size"),
      );
    }

    const sizeNum = Number(size.value);
    const data = new Array(sizeNum).fill(initialValue);
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

  // Start map_get/2
  "map_get/2": (key, map) => {
    if (!Type.isMap(map)) {
      Interpreter.raiseBadMapError(map);
    }

    const encodedKey = Type.encodeMapKey(key);
    if (!(encodedKey in map.data)) {
      throw new HologramBoxedError(
        Type.tuple([Type.atom("badkey"), key])
      );
    }

    return map.data[encodedKey];
  },
  // End map_get/2
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
      bytes = data.bytes;
    } else if (Type.isList(data)) {
      // Convert iolist to binary first
      const binary = Erlang["iolist_to_binary/1"](data);
      Bitstring.maybeSetBytesFromText(binary);
      bytes = binary.bytes;
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or iolist"),
      );
    }

    // Simple MD5 implementation (placeholder - would need full implementation for production)
    // For now, return a 16-byte hash
    throw new HologramInterpreterError(
      "Function :erlang.md5/1 is not yet fully implemented in Hologram.\n" +
      "MD5 hashing requires a crypto library which is not yet integrated.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End md5/1
  // Deps: [:erlang.iolist_to_binary/1]

  // Start monotonic_time/0
  "monotonic_time/0": () => {
    // Return monotonic time in native time unit (nanoseconds)
    // Using performance.now() which provides monotonic time in milliseconds
    const timeMs = performance.now();
    const timeNs = BigInt(Math.floor(timeMs * 1_000_000));
    return Type.integer(timeNs);
  },
  // End monotonic_time/0
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

  // Start node/0
  "node/0": () => {
    // Return the current node name
    // In Hologram, we use a default node name
    return Type.atom("nonode@nohost");
  },
  // End node/0
  // Deps: []

  // Start now/0
  "now/0": () => {
    // Return timestamp as {MegaSecs, Secs, MicroSecs} (deprecated but still used)
    // This is similar to timestamp/0
    return Erlang["timestamp/0"]();
  },
  // End now/0
  // Deps: [:erlang.timestamp/0]

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

  // Start put/2
  "put/2": (key, value) => {
    // Store key-value pair in process dictionary
    // In Hologram, we simulate this with a global process dictionary
    if (!globalThis.__hologramProcessDict) {
      globalThis.__hologramProcessDict = new Map();
    }

    // Get the previous value if it exists
    const prevValue = globalThis.__hologramProcessDict.get(
      Type.encodeMapKey(key)
    );

    // Store the new value with encoded key
    globalThis.__hologramProcessDict.set(Type.encodeMapKey(key), value);

    // Return the previous value or undefined atom
    return prevValue !== undefined ? prevValue : Type.atom("undefined");
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

    // Convert PID to string representation, then to list of character codes
    const str = pid.value;
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End pid_to_list/1
  // Deps: []

  // Start port_to_list/1
  "port_to_list/1": (port) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    // Convert port to string representation, then to list of character codes
    const str = port.value;
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End port_to_list/1
  // Deps: []

  // Start phash2/1
  "phash2/1": (term) => {
    return Erlang["phash2/2"](term, Type.integer(BigInt(27)));
  },
  // End phash2/1
  // Deps: [:erlang.phash2/2]

  // Start phash2/2
  "phash2/2": (term, range) => {
    if (!Type.isInteger(range)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Simple hash function - in production would use a proper portable hash
    const termStr = JSON.stringify(term);
    let hash = 0;
    for (let i = 0; i < termStr.length; i++) {
      hash = ((hash << 5) - hash) + termStr.charCodeAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }

    const rangeNum = Number(range.value);
    return Type.integer(BigInt(Math.abs(hash) % rangeNum));
  },
  // End phash2/2
  // Deps: []

  // Start processes/0
  "processes/0": () => {
    // In Hologram, return a list with just the current process
    // Full implementation would require process tracking
    return Type.list([Type.pid("<0.0.0>")]);
  },
  // End processes/0
  // Deps: []

  // Start register/2
  "register/2": (name, pid) => {
    if (!Type.isAtom(name)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a pid"),
      );
    }

    // Store in global registry
    if (!globalThis.__hologramProcessRegistry) {
      globalThis.__hologramProcessRegistry = new Map();
    }

    const nameStr = name.value;
    if (globalThis.__hologramProcessRegistry.has(nameStr)) {
      throw new HologramBoxedError(
        Type.tuple([Type.atom("error"), Type.tuple([Type.atom("already_registered"), name])])
      );
    }

    globalThis.__hologramProcessRegistry.set(nameStr, pid);
    return Type.atom("true");
  },
  // End register/2
  // Deps: []

  // Start registered/0
  "registered/0": () => {
    // Return list of registered process names
    if (!globalThis.__hologramProcessRegistry) {
      globalThis.__hologramProcessRegistry = new Map();
    }

    const names = Array.from(globalThis.__hologramProcessRegistry.keys()).map(
      (name) => Type.atom(name)
    );

    return Type.list(names);
  },
  // End registered/0
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

    // Convert reference to string representation, then to list of character codes
    const str = ref.value;
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End ref_to_list/1
  // Deps: []

  // Start round/1
  "round/1": (number) => {
    if (Type.isInteger(number)) {
      return number;
    } else if (Type.isFloat(number)) {
      return Type.integer(BigInt(Math.round(number.value)));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
  },
  // End round/1
  // Deps: []

  // Start self/0
  "self/0": () => {
    // Return a fixed PID for the client process
    return Type.pid("client", [0, 0, 0], "client");
  },
  // End self/0
  // Deps: []

  // Start send/2
  "send/2": (dest, message) => {
    // On client-side, this is a simplified version
    // Just return the message as per Erlang semantics
    // Validation: dest should be a PID or atom
    if (!Type.isPid(dest) && !Type.isAtom(dest)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or atom"),
      );
    }
    return message;
  },
  // End send/2
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

    const idx = Number(index.value);
    if (idx < 1 || idx > tuple.data.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "out of range"),
      );
    }

    // Create a new tuple with the element replaced
    const newData = [...tuple.data];
    newData[idx - 1] = value;
    return Type.tuple(newData);
  },
  // End setelement/3
  // Deps: []

  // Start spawn/1
  "spawn/1": (fun) => {
    if (!Type.isAnonymousFunction(fun) || fun.arity !== 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function of arity 0"),
      );
    }

    // Return a unique PID (using timestamp and random number)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    return Type.pid("client", [0, timestamp, random], "client");
  },
  // End spawn/1
  // Deps: []

  // Start spawn/3
  "spawn/3": (module, functionName, args) => {
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

    // Return a unique PID (using timestamp and random number)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    return Type.pid("client", [0, timestamp, random], "client");
  },
  // End spawn/3
  // Deps: []

  // Start size/1
  "size/1": (term) => {
    if (Type.isTuple(term)) {
      return Type.integer(term.data.length);
    } else if (Type.isBinary(term)) {
      Bitstring.maybeSetBytesFromText(term);
      return Type.integer(term.bytes.length);
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a tuple or binary"),
    );
  },
  // End size/1
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

  // Start system_time/0
  "system_time/0": () => {
    // Return system time in native time unit (nanoseconds)
    // Using Date.now() which provides time in milliseconds since Unix epoch
    const timeMs = Date.now();
    const timeNs = BigInt(timeMs) * 1_000_000n;
    return Type.integer(timeNs);
  },
  // End system_time/0
  // Deps: []

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

  // Start timestamp/0
  "timestamp/0": () => {
    // Return current timestamp as {MegaSecs, Secs, MicroSecs}
    // Compatible with Erlang's erlang:timestamp/0
    const now = Date.now(); // milliseconds since epoch
    const microSecs = now * 1000; // convert to microseconds
    const megaSecs = Math.floor(microSecs / 1_000_000_000_000);
    const secs = Math.floor((microSecs % 1_000_000_000_000) / 1_000_000);
    const micros = Math.floor(microSecs % 1_000_000);

    return Type.tuple([
      Type.integer(BigInt(megaSecs)),
      Type.integer(BigInt(secs)),
      Type.integer(BigInt(micros)),
    ]);
  },
  // End timestamp/0
  // Deps: []

  // Start term_to_binary/1
  "term_to_binary/1": (term) => {
    // ETF (External Term Format) serialization is complex
    // This would require a full implementation of Erlang's term encoding
    throw new HologramInterpreterError(
      "Function :erlang.term_to_binary/1 is not yet fully implemented in Hologram.\n" +
      "Serializing to Erlang External Term Format requires complex binary encoding.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End term_to_binary/1
  // Deps: []

  // Start throw/1
  "throw/1": (term) => {
    // Throw an exception with the given term
    throw new HologramBoxedError(
      Type.tuple([Type.atom("throw"), term])
    );
  },
  // End throw/1
  // Deps: []

  // Start time/0
  "time/0": () => {
    // Return current time as {Hour, Minute, Second}
    const now = new Date();
    return Type.tuple([
      Type.integer(BigInt(now.getHours())),
      Type.integer(BigInt(now.getMinutes())),
      Type.integer(BigInt(now.getSeconds())),
    ]);
  },
  // End time/0
  // Deps: []

  // Start trunc/1
  "trunc/1": (number) => {
    if (Type.isInteger(number)) {
      return number;
    } else if (Type.isFloat(number)) {
      return Type.integer(BigInt(Math.trunc(number.value)));
    }

    Interpreter.raiseArgumentError(
      Interpreter.buildArgumentErrorMsg(1, "not a number"),
    );
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

  // Start tuple_size/1
  "tuple_size/1": (tuple) => {
    if (!Type.isTuple(tuple)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    return Type.integer(tuple.data.length);
  },
  // End tuple_size/1
  // Deps: []

  // Start unique_integer/0
  "unique_integer/0": () => {
    // Generate a unique integer using timestamp and counter
    if (!globalThis.__hologramUniqueIntegerCounter) {
      globalThis.__hologramUniqueIntegerCounter = 0n;
    }

    const counter = globalThis.__hologramUniqueIntegerCounter++;
    const timestamp = BigInt(Date.now());
    const unique = (timestamp << 32n) | counter;

    return Type.integer(unique);
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

    if (!Type.isProperList(modifiers)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a proper list"),
      );
    }

    // Check for valid modifiers (positive, monotonic)
    let isPositive = false;
    for (const modifier of modifiers.data) {
      if (Interpreter.isStrictlyEqual(modifier, Type.atom("positive"))) {
        isPositive = true;
      } else if (!Interpreter.isStrictlyEqual(modifier, Type.atom("monotonic"))) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "invalid modifier"),
        );
      }
    }

    const unique = Erlang["unique_integer/0"]();

    // If positive modifier is set, ensure the result is positive
    if (isPositive && unique.value < 0n) {
      return Type.integer(-unique.value);
    }

    return unique;
  },
  // End unique_integer/1
  // Deps: [:erlang.unique_integer/0]

  // Start universaltime/0
  "universaltime/0": () => {
    // Return UTC time as {{Year, Month, Day}, {Hour, Minute, Second}}
    const now = new Date();
    return Type.tuple([
      Type.tuple([
        Type.integer(BigInt(now.getUTCFullYear())),
        Type.integer(BigInt(now.getUTCMonth() + 1)),
        Type.integer(BigInt(now.getUTCDate())),
      ]),
      Type.tuple([
        Type.integer(BigInt(now.getUTCHours())),
        Type.integer(BigInt(now.getUTCMinutes())),
        Type.integer(BigInt(now.getUTCSeconds())),
      ]),
    ]);
  },
  // End universaltime/0
  // Deps: []

  // Start unregister/1
  "unregister/1": (name) => {
    if (!Type.isAtom(name)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!globalThis.__hologramProcessRegistry) {
      globalThis.__hologramProcessRegistry = new Map();
    }

    const nameStr = name.value;
    if (!globalThis.__hologramProcessRegistry.has(nameStr)) {
      throw new HologramBoxedError(
        Type.tuple([Type.atom("error"), Type.tuple([Type.atom("not_registered"), name])])
      );
    }

    globalThis.__hologramProcessRegistry.delete(nameStr);
    return Type.atom("true");
  },
  // End unregister/1
  // Deps: []

  // Start whereis/1
  "whereis/1": (name) => {
    if (!Type.isAtom(name)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!globalThis.__hologramProcessRegistry) {
      globalThis.__hologramProcessRegistry = new Map();
    }

    const nameStr = name.value;
    const pid = globalThis.__hologramProcessRegistry.get(nameStr);

    return pid !== undefined ? pid : Type.atom("undefined");
  },
  // End whereis/1
  // Deps: []
};

export default Erlang;
