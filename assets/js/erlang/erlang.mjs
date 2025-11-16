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

  // Start !/2
  "!/2": (dest, message) => {
    // Send operator (same as send/2)
    return Erlang["send/2"](dest, message);
  },
  // End !/2
  // Deps: [:erlang.send/2]

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

  // Start =/2
  "=/2": (left, right) => {
    // Match operator (pattern matching in Erlang)
    // In Hologram, this is simplified to check equality
    // Returns right if match succeeds, otherwise raises badmatch
    if (Interpreter.isStrictlyEqual(left, right)) {
      return right;
    }

    // In a full implementation, this would do pattern matching
    // For now, raise badmatch error
    throw new HologramBoxedError(
      Type.tuple([Type.atom("badmatch"), right])
    );
  },
  // End =/2
  // Deps: []

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

  // Start alias/0
  "alias/0": () => {
    // Create an alias (reference) for the current process
    // Aliases are used for selective receive in modern Erlang
    return Erlang["make_ref/0"]();
  },
  // End alias/0
  // Deps: [:erlang.make_ref/0]

  // Start alias/1
  "alias/1": (options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    // Create an alias with options
    // Options can include: explicit_unalias
    return Erlang["make_ref/0"]();
  },
  // End alias/1
  // Deps: [:erlang.make_ref/0]

  // Start adler32/1
  "adler32/1": (data) => {
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    // Adler-32 checksum algorithm
    Bitstring.maybeSetBytesFromText(data);
    const bytes = data.bytes;

    let a = 1;
    let b = 0;
    const MOD_ADLER = 65521;

    for (let i = 0; i < bytes.length; i++) {
      a = (a + bytes[i]) % MOD_ADLER;
      b = (b + a) % MOD_ADLER;
    }

    const checksum = (b << 16) | a;
    return Type.integer(BigInt(checksum >>> 0)); // Convert to unsigned
  },
  // End adler32/1
  // Deps: []

  // Start adler32/2
  "adler32/2": (oldAdler, data) => {
    if (!Type.isInteger(oldAdler)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a binary"),
      );
    }

    // Continue Adler-32 checksum from previous value
    Bitstring.maybeSetBytesFromText(data);
    const bytes = data.bytes;

    const prevChecksum = Number(oldAdler.value);
    let a = prevChecksum & 0xffff;
    let b = (prevChecksum >>> 16) & 0xffff;
    const MOD_ADLER = 65521;

    for (let i = 0; i < bytes.length; i++) {
      a = (a + bytes[i]) % MOD_ADLER;
      b = (b + a) % MOD_ADLER;
    }

    const checksum = (b << 16) | a;
    return Type.integer(BigInt(checksum >>> 0));
  },
  // End adler32/2
  // Deps: []

  // Start adler32_combine/3
  "adler32_combine/3": (adler1, adler2, size2) => {
    if (!Type.isInteger(adler1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(adler2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(size2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    // Combine two Adler-32 checksums
    // This is a simplified implementation
    const MOD_ADLER = 65521;
    const a1 = Number(adler1.value) & 0xffff;
    const b1 = (Number(adler1.value) >>> 16) & 0xffff;
    const a2 = Number(adler2.value) & 0xffff;
    const b2 = (Number(adler2.value) >>> 16) & 0xffff;
    const len2 = Number(size2.value);

    // Combine the checksums
    let a = (a1 + a2 - 1) % MOD_ADLER;
    let b = (b1 + b2 + (len2 * a1)) % MOD_ADLER;

    const checksum = (b << 16) | a;
    return Type.integer(BigInt(checksum >>> 0));
  },
  // End adler32_combine/3
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
  "and/2": (boolean1, boolean2) => {
    if (!Type.isBoolean(boolean1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(boolean2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    // Logical AND operation
    return Type.boolean(boolean1.value && boolean2.value);
  },
  // End and/2
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

  // Start append/2
  "append/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Concatenate two lists
    // In Erlang, this is the same as list1 ++ list2
    return Erlang["++/2"](list1, list2);
  },
  // End append/2
  // Deps: [:erlang.++/2]

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

  // Start apply/1
  "apply/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Apply a function with no arguments
    return fun.call();
  },
  // End apply/1
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

  // Start atom_to_binary/3
  "atom_to_binary/3": (atom, inEncoding, outEncoding) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(inEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isAtom(outEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an atom"),
      );
    }

    // For now, ignore encodings and just convert atom to binary
    return Type.bitstring(atom.value);
  },
  // End atom_to_binary/3
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

  // Start atom_to_list/2
  "atom_to_list/2": (atom, encoding) => {
    if (!Type.isAtom(atom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(encoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Convert atom to list with encoding (for now ignore encoding)
    return Bitstring.toCodepoints(Type.bitstring(atom.value));
  },
  // End atom_to_list/2
  // Deps: []

  // Start band/2
  "band/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(integer2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Bitwise AND operation
    return Type.integer(integer1.value & integer2.value);
  },
  // End band/2
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

  // Start binary_to_atom/3
  "binary_to_atom/3": (binary, inEncoding, outEncoding) => {
    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    if (!Type.isAtom(inEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isAtom(outEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an atom"),
      );
    }

    // Convert binary to atom with encoding (for now ignore encoding)
    return Type.atom(Bitstring.toText(binary));
  },
  // End binary_to_atom/3
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

  // Start binary_to_existing_atom/3
  "binary_to_existing_atom/3": (binary, inEncoding, outEncoding) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isAtom(inEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isAtom(outEncoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an atom"),
      );
    }

    // For now, ignore encodings and use binary_to_existing_atom/2
    return Erlang["binary_to_existing_atom/2"](binary, inEncoding);
  },
  // End binary_to_existing_atom/3
  // Deps: [:erlang.binary_to_existing_atom/2]

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

  // Start binary_to_float/2
  "binary_to_float/2": (binary, options) => {
    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Convert binary to float with options (for now ignore options)
    const text = Bitstring.toText(binary);
    const floatValue = parseFloat(text);

    if (isNaN(floatValue)) {
      Interpreter.raiseArgumentError("not a valid float");
    }

    return Type.float(floatValue);
  },
  // End binary_to_float/2
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

  // Start binary_to_integer/3
  "binary_to_integer/3": (binary, base, options) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(base)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Convert binary to integer with base and options (OTP 26+)
    // For now, ignore options and use binary_to_integer/2
    return Erlang["binary_to_integer/2"](binary, base);
  },
  // End binary_to_integer/3
  // Deps: [:erlang.binary_to_integer/2]

  // Start binary_part/2
  "binary_part/2": (binary, posLen) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isTuple(posLen) || posLen.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid position/length tuple"),
      );
    }

    const start = posLen.data[0];
    const length = posLen.data[1];

    if (!Type.isInteger(start)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "position is not an integer"),
      );
    }

    if (!Type.isInteger(length)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "length is not an integer"),
      );
    }

    // Use binary_part/3 to do the actual work
    return Erlang["binary_part/3"](binary, start, length);
  },
  // End binary_part/2
  // Deps: [:erlang.binary_part/3]

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

  // Start binary_to_list/2
  "binary_to_list/2": (binary, encoding) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isAtom(encoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Convert binary to list with encoding (for now ignore encoding)
    const bytes = Array.from(binary.bytes);
    return Type.list(bytes.map((byte) => Type.integer(byte)));
  },
  // End binary_to_list/2
  // Deps: []

  // Start binary_to_pid/1
  "binary_to_pid/1": (binary) => {
    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    // Convert binary to PID
    // In Hologram, we'll convert the binary string representation back to PID
    const str = binary.value;
    return Type.pid(str);
  },
  // End binary_to_pid/1
  // Deps: []

  // Start binary_to_port/1
  "binary_to_port/1": (binary) => {
    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    // Convert binary to port
    // In Hologram, we'll convert the binary string representation back to port
    const str = binary.value;
    return Type.port(str);
  },
  // End binary_to_port/1
  // Deps: []

  // Start binary_to_ref/1
  "binary_to_ref/1": (binary) => {
    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a bitstring"),
      );
    }

    // Convert binary to reference
    // In Hologram, we'll convert the binary string representation back to reference
    const str = binary.value;
    return Type.reference(str);
  },
  // End binary_to_ref/1
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

  // Start binary_to_term/2
  "binary_to_term/2": (binary, opts) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isList(opts)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // ETF (External Term Format) deserialization is complex
    // This would require a full implementation of Erlang's term encoding
    throw new HologramInterpreterError(
      "Function :erlang.binary_to_term/2 is not yet fully implemented in Hologram.\n" +
      "Deserializing Erlang External Term Format requires complex binary parsing.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End binary_to_term/2
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

  // Start bnot/1
  "bnot/1": (integer) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // Bitwise NOT operation
    return Type.integer(~integer.value);
  },
  // End bnot/1
  // Deps: []

  // Start bor/2
  "bor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(integer2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Bitwise OR operation
    return Type.integer(integer1.value | integer2.value);
  },
  // End bor/2
  // Deps: []

  // Start bsl/2
  "bsl/2": (integer, shift) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(shift)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Bit shift left operation
    return Type.integer(integer.value << shift.value);
  },
  // End bsl/2
  // Deps: []

  // Start bsr/2
  "bsr/2": (integer, shift) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(shift)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Bit shift right operation (arithmetic shift)
    return Type.integer(integer.value >> shift.value);
  },
  // End bsr/2
  // Deps: []

  // Start bxor/2
  "bxor/2": (integer1, integer2) => {
    if (!Type.isInteger(integer1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(integer2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Bitwise XOR operation
    return Type.integer(integer1.value ^ integer2.value);
  },
  // End bxor/2
  // Deps: []

  // Start bump_reductions/1
  "bump_reductions/1": (reductions) => {
    if (!Type.isInteger(reductions)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // In a browser environment, we can't actually bump reductions
    // This is primarily a scheduler hint in Erlang
    // Just return true to indicate success
    return Type.boolean(true);
  },
  // End bump_reductions/1
  // Deps: []

  // Start cancel_timer/1
  "cancel_timer/1": (timerRef) => {
    if (!Type.isReference(timerRef)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    // Check if timer exists in global timer registry
    if (!globalThis.__hologramTimers) {
      globalThis.__hologramTimers = {};
    }

    const timerId = timerRef.value;
    if (globalThis.__hologramTimers[timerId]) {
      clearTimeout(globalThis.__hologramTimers[timerId].timeoutId);
      const remaining = globalThis.__hologramTimers[timerId].remaining;
      delete globalThis.__hologramTimers[timerId];
      return Type.integer(BigInt(Math.max(0, remaining)));
    }

    return Type.boolean(false);
  },
  // End cancel_timer/1
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

  // Start decode_packet/3
  "decode_packet/3": (type, binary, options) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a bitstring"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Decode packet from binary
    // Types: raw, 0, 1, 2, 4, asn1, cdr, sunrm, fcgi, tpkt, line, http, http_bin, httph, httph_bin
    // In Hologram (browser environment), packet decoding is not fully supported
    // Return a simple decoded format
    return Type.tuple([
      Type.atom("ok"),
      binary,
      Type.bitstring(""),
    ]);
  },
  // End decode_packet/3
  // Deps: []

  // Start delete/2
  "delete/2": (element, list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Delete first occurrence of element from list
    const result = [];
    let deleted = false;

    for (let i = 0; i < list.data.length; i += 2) {
      const item = list.data[i];
      const rest = list.data[i + 1];

      if (!deleted && Interpreter.isStrictlyEqual(item, element)) {
        deleted = true;
        // Skip this element, continue with rest
        if (rest && Type.isList(rest)) {
          // Continue processing the rest
          for (let j = 0; j < rest.data.length; j++) {
            result.push(rest.data[j]);
          }
          break;
        }
      } else {
        result.push(item);
        if (rest && Type.isList(rest) && rest.data.length > 0) {
          // Continue to next iteration
          continue;
        }
      }
    }

    // Simpler implementation: convert to array, filter, convert back
    const flatList = [];
    let current = list;
    while (Type.isList(current) && current.data.length > 0) {
      flatList.push(current.data[0]);
      current = current.data[1] || Type.list([]);
    }

    // Remove first occurrence
    const index = flatList.findIndex(item => Interpreter.isStrictlyEqual(item, element));
    if (index !== -1) {
      flatList.splice(index, 1);
    }

    return Type.list(flatList);
  },
  // End delete/2
  // Deps: []

  // Start disconnect_node/1
  "disconnect_node/1": (node) => {
    if (!Type.isAtom(node)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Disconnect from a distributed node
    // In Hologram (browser environment), distributed nodes are not supported
    // Return false (node not connected)
    return Type.boolean(false);
  },
  // End disconnect_node/1
  // Deps: []

  // Start delete_module/1
  "delete_module/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Delete module from system
    // In Hologram, we don't have code loading, so just return true
    return Type.boolean(true);
  },
  // End delete_module/1
  // Deps: []

  // Start demonitor/1
  "demonitor/1": (monitorRef) => {
    if (!Type.isReference(monitorRef)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    // In Hologram, demonitoring is simplified
    // Just return true to indicate success
    return Type.boolean(true);
  },
  // End demonitor/1
  // Deps: []

  // Start demonitor/2
  "demonitor/2": (monitorRef, options) => {
    if (!Type.isReference(monitorRef)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Remove a monitor with options
    // Options can include: flush, info
    // In Hologram, demonitoring is simplified
    return Type.boolean(true);
  },
  // End demonitor/2
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

  // Start convert_time_unit/3
  "convert_time_unit/3": (time, fromUnit, toUnit) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isAtom(fromUnit)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isAtom(toUnit)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an atom"),
      );
    }

    // Define conversion rates to nanoseconds
    const toNanoseconds = {
      second: 1_000_000_000n,
      millisecond: 1_000_000n,
      microsecond: 1_000n,
      nanosecond: 1n,
      native: 1n, // Treat native as nanoseconds
    };

    const fromRate = toNanoseconds[fromUnit.value];
    const toRate = toNanoseconds[toUnit.value];

    if (!fromRate || !toRate) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "invalid time unit"),
      );
    }

    // Convert: time * fromRate / toRate
    const timeValue = time.value;
    const result = (timeValue * fromRate) / toRate;

    return Type.integer(result);
  },
  // End convert_time_unit/3
  // Deps: []

  // Start copy/1
  "copy/1": (term) => {
    // Copy a term (makes a deep copy for mutable structures)
    // In Hologram, terms are immutable, so just return the term
    return term;
  },
  // End copy/1
  // Deps: []

  // Start copy/2
  "copy/2": (term, count) => {
    if (!Type.isInteger(count)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (count.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a non-negative integer"),
      );
    }

    // Create a list of count copies of term
    const copies = [];
    for (let i = 0n; i < count.value; i++) {
      copies.push(term);
    }
    return Type.list(copies);
  },
  // End copy/2
  // Deps: []

  // Start crc32/1
  "crc32/1": (data) => {
    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    // CRC-32 checksum algorithm
    Bitstring.maybeSetBytesFromText(data);
    const bytes = data.bytes;

    // CRC-32 lookup table
    const crcTable = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
      let c = i;
      for (let j = 0; j < 8; j++) {
        c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      crcTable[i] = c;
    }

    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) {
      crc = crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }

    return Type.integer(BigInt((crc ^ 0xFFFFFFFF) >>> 0));
  },
  // End crc32/1
  // Deps: []

  // Start crc32/2
  "crc32/2": (oldCrc, data) => {
    if (!Type.isInteger(oldCrc)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isBinary(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a binary"),
      );
    }

    // Continue CRC-32 checksum from previous value
    Bitstring.maybeSetBytesFromText(data);
    const bytes = data.bytes;

    // CRC-32 lookup table
    const crcTable = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
      let c = i;
      for (let j = 0; j < 8; j++) {
        c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      crcTable[i] = c;
    }

    let crc = Number(oldCrc.value) ^ 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) {
      crc = crcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }

    return Type.integer(BigInt((crc ^ 0xFFFFFFFF) >>> 0));
  },
  // End crc32/2
  // Deps: []

  // Start crc32_combine/3
  "crc32_combine/3": (crc1, crc2, size2) => {
    if (!Type.isInteger(crc1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isInteger(crc2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(size2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    // Combine two CRC-32 checksums
    // This is a simplified implementation
    // In practice, CRC combination requires more complex mathematics
    const combined = Number(crc1.value) ^ Number(crc2.value);
    return Type.integer(BigInt(combined >>> 0));
  },
  // End crc32_combine/3
  // Deps: []

  // Start check_old_code/1
  "check_old_code/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Check if old code exists for module
    // In Hologram, we don't have code loading, so return false
    return Type.boolean(false);
  },
  // End check_old_code/1
  // Deps: []

  // Start check_process_code/2
  "check_process_code/2": (pid, module) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Check if process is executing old code
    // In Hologram, we don't have code loading, so return false
    return Type.boolean(false);
  },
  // End check_process_code/2
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

  // Start exit/2
  "exit/2": (pid, reason) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // Exit signal to another process
    // In Hologram, we can't actually send exit signals between processes
    // Just return true to indicate the signal was sent
    return Type.boolean(true);
  },
  // End exit/2
  // Deps: []

  // Start external_size/1
  "external_size/1": (term) => {
    // Calculate the external term format size
    // This is a simplified implementation - actual ETF encoding is complex
    // For now, return an approximation based on term type

    if (Type.isAtom(term)) {
      // Atom: 1 byte tag + 2 bytes length + UTF-8 bytes
      return Type.integer(BigInt(3 + term.value.length * 2));
    } else if (Type.isInteger(term)) {
      // Small/big integer: varies by size
      const absValue = term.value < 0n ? -term.value : term.value;
      if (absValue < 256n) {
        return Type.integer(2n); // SMALL_INTEGER_EXT
      } else if (absValue < 2147483648n) {
        return Type.integer(5n); // INTEGER_EXT
      } else {
        // Estimate for big integers
        const bytes = absValue.toString(16).length / 2;
        return Type.integer(BigInt(Math.ceil(bytes) + 4));
      }
    } else if (Type.isFloat(term)) {
      return Type.integer(9n); // NEW_FLOAT_EXT: 1 + 8 bytes
    } else if (Type.isBitstring(term)) {
      Bitstring.maybeSetBytesFromText(term);
      return Type.integer(BigInt(6 + term.bytes.length)); // BINARY_EXT
    } else if (Type.isTuple(term)) {
      // Tuple: tag + size + elements
      let size = term.data.length < 256 ? 2n : 5n;
      for (const elem of term.data) {
        size += Erlang["external_size/1"](elem).value;
      }
      return Type.integer(size);
    } else if (Type.isList(term)) {
      // List: elements + NIL_EXT
      let size = 1n; // NIL_EXT
      let current = term;
      while (Type.isList(current) && current.data.length > 0) {
        size += 5n; // LIST_EXT overhead
        size += Erlang["external_size/1"](current.data[0]).value;
        current = current.data[1] || Type.list([]);
      }
      return Type.integer(size);
    } else if (Type.isPid(term)) {
      return Type.integer(13n); // PID_EXT
    } else if (Type.isReference(term)) {
      return Type.integer(15n); // NEW_REFERENCE_EXT (approximate)
    } else if (Type.isPort(term)) {
      return Type.integer(11n); // PORT_EXT
    } else if (Type.isMap(term)) {
      // Map: tag + size + key-value pairs
      const keys = Object.keys(term.data);
      let size = 5n; // MAP_EXT tag + size
      for (const key of keys) {
        const decodedKey = Type.decodeMapKey(key);
        size += Erlang["external_size/1"](decodedKey).value;
        size += Erlang["external_size/1"](term.data[key]).value;
      }
      return Type.integer(size);
    }

    // Default case
    return Type.integer(10n);
  },
  // End external_size/1
  // Deps: []

  // Start external_size/2
  "external_size/2": (term, options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Calculate external term format size with options
    // Options can include: {minor_version, Version}
    // For now, use same logic as external_size/1
    return Erlang["external_size/1"](term);
  },
  // End external_size/2
  // Deps: [:erlang.external_size/1]

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

  // Start float_to_integer/1
  "float_to_integer/1": (float) => {
    if (!Type.isFloat(float)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    }

    // Convert float to integer by truncating
    return Type.integer(BigInt(Math.trunc(float.value)));
  },
  // End float_to_integer/1
  // Deps: []

  // Start float_to_binary/1
  "float_to_binary/1": (float) => {
    if (!Type.isFloat(float)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a float"),
      );
    }

    // Default formatting - use scientific notation with precision
    const str = float.value.toExponential();
    return Type.bitstring(str);
  },
  // End float_to_binary/1
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

    // Options can include: {decimals, N}, {scientific, N}, compact
    // For now, use simple string conversion
    const str = String(float.value);
    const charCodes = [...str].map((char) =>
      Type.integer(BigInt(char.charCodeAt(0))),
    );

    return Type.list(charCodes);
  },
  // End float_to_list/2
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

  // Start format_status/2
  "format_status/2": (opt, statusData) => {
    if (!Type.isAtom(opt)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isList(statusData)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Format process status for sys:get_status/1,2
    // opt can be: normal, terminate
    // In Hologram, return a simple formatted status
    return statusData;
  },
  // End format_status/2
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

  // Start behaviour_info/1
  "behaviour_info/1": (item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Get behaviour information
    // This is used to query behaviour callbacks
    // In Hologram, return undefined (no behaviour info available)
    return Type.atom("undefined");
  },
  // End behaviour_info/1
  // Deps: []

  // Start fun_info/1
  "fun_info/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Return basic function info as a list of tuples
    const info = [
      Type.tuple([Type.atom("type"), Type.atom("local")]),
      Type.tuple([Type.atom("arity"), Type.integer(BigInt(fun.arity || 0))]),
    ];

    return Type.list(info);
  },
  // End fun_info/1
  // Deps: []

  // Start fun_info/2
  "fun_info/2": (fun, item) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const itemName = item.value;

    switch (itemName) {
      case "type":
        return Type.tuple([Type.atom("type"), Type.atom("local")]);
      case "arity":
        return Type.tuple([Type.atom("arity"), Type.integer(BigInt(fun.arity || 0))]);
      default:
        throw new HologramBoxedError(
          Type.tuple([Type.atom("badarg"), item])
        );
    }
  },
  // End fun_info/2
  // Deps: []

  // Start fun_to_list/1
  "fun_to_list/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Convert function to string representation, then to list of character codes
    const str = `#Fun<${fun.arity}>`;
    const charCodes = Array.from(str).map((char) =>
      Type.integer(char.charCodeAt(0))
    );

    return Type.list(charCodes);
  },
  // End fun_to_list/1
  // Deps: []

  // Start fun_to_binary/1
  "fun_to_binary/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Convert function to binary
    // In Hologram (browser environment), we can't serialize functions to BEAM binary format
    Interpreter.raiseHologramInterpreterError(
      "fun_to_binary/1 is not supported in browser environment",
    );
  },
  // End fun_to_binary/1
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

  // Start get_stacktrace/0
  "get_stacktrace/0": () => {
    // Get the stacktrace of the last exception
    // This is deprecated in favor of try/catch with stacktrace variable
    // In Hologram, return an empty stacktrace
    return Type.list([]);
  },
  // End get_stacktrace/0
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

  // Start get_cookie/0
  "get_cookie/0": () => {
    // Get magic cookie for distributed Erlang
    // In Hologram, return a default cookie
    return Type.atom("hologram_cookie");
  },
  // End get_cookie/0
  // Deps: []

  // Start garbage_collect/0
  "garbage_collect/0": () => {
    // In browser/Node.js, we can't force garbage collection explicitly
    // This is a no-op in Hologram
    return Type.boolean(true);
  },
  // End garbage_collect/0
  // Deps: []

  // Start group_leader/0
  "group_leader/0": () => {
    // Return the group leader process (simplified in Hologram)
    return Type.pid("<0.0.0>");
  },
  // End group_leader/0
  // Deps: []

  // Start group_leader/2
  "group_leader/2": (leader, pid) => {
    if (!Type.isPid(leader)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a pid"),
      );
    }

    // Set the group leader of a process
    // In Hologram, we can't actually set group leaders
    // Just return true to indicate success
    return Type.boolean(true);
  },
  // End group_leader/2
  // Deps: []

  // Start hash/2
  "hash/2": (term, range) => {
    if (!Type.isInteger(range)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const rangeNum = Number(range.value);
    if (rangeNum < 1 || rangeNum > 2 ** 27) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "range must be between 1 and 2^27"),
      );
    }

    // Simple hash function (not cryptographic)
    // Convert term to string and hash it
    const str = Interpreter.inspect(term);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }

    // Return hash in range [1, range]
    const result = (Math.abs(hash) % rangeNum) + 1;
    return Type.integer(BigInt(result));
  },
  // End hash/2
  // Deps: []

  // Start hibernate/3
  "hibernate/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
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

    // Hibernate reduces process memory and waits for a message
    // In Hologram, we can't truly hibernate, so just return a PID
    // This is a placeholder implementation
    return Type.pid("<0.0.0>");
  },
  // End hibernate/3
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

  // Start integer_to_float/1
  "integer_to_float/1": (integer) => {
    if (!Type.isInteger(integer)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    // Convert integer to float
    return Type.float(Number(integer.value));
  },
  // End integer_to_float/1
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

  // Start iolist_to_binary/2
  "iolist_to_binary/2": (iolist, options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Convert iolist to binary with options (for now ignore options)
    return Erlang["iolist_to_binary/1"](iolist);
  },
  // End iolist_to_binary/2
  // Deps: [:erlang.iolist_to_binary/1]

  // Start iolist_to_iovec/1
  "iolist_to_iovec/1": (iolist) => {
    // Convert iolist to iovec (list of binaries)
    // For simplicity, just convert to a single binary and return as list
    const binary = Erlang["iolist_to_binary/1"](iolist);
    return Type.list([binary]);
  },
  // End iolist_to_iovec/1
  // Deps: [:erlang.iolist_to_binary/1]

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

  // Start is_alive/0
  "is_alive/0": () => {
    // In Hologram, we always consider the node alive
    return Type.boolean(true);
  },
  // End is_alive/0
  // Deps: []

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

  // Start is_process_alive/1
  "is_process_alive/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // In Hologram, we can't actually check if a process is alive
    // For now, always return true for any valid PID
    // In a real implementation, this would check the process registry
    return Type.boolean(true);
  },
  // End is_process_alive/1
  // Deps: []

  // Start is_reference/1
  "is_reference/1": (term) => {
    return Type.boolean(Type.isReference(term));
  },
  // End is_reference/1
  // Deps: []

  // Start is_record/2
  "is_record/2": (term, recordTag) => {
    if (!Type.isAtom(recordTag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Check if term is a record (tuple with first element as tag)
    if (!Type.isTuple(term)) {
      return Type.boolean(false);
    }

    if (term.data.length === 0) {
      return Type.boolean(false);
    }

    const firstElem = term.data[0];
    if (!Type.isAtom(firstElem)) {
      return Type.boolean(false);
    }

    return Type.boolean(firstElem.value === recordTag.value);
  },
  // End is_record/2
  // Deps: []

  // Start is_record/3
  "is_record/3": (term, recordTag, size) => {
    if (!Type.isAtom(recordTag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isInteger(size)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    // Check if term is a record with specific size
    if (!Type.isTuple(term)) {
      return Type.boolean(false);
    }

    if (term.data.length !== Number(size.value)) {
      return Type.boolean(false);
    }

    if (term.data.length === 0) {
      return Type.boolean(false);
    }

    const firstElem = term.data[0];
    if (!Type.isAtom(firstElem)) {
      return Type.boolean(false);
    }

    return Type.boolean(firstElem.value === recordTag.value);
  },
  // End is_record/3
  // Deps: []

  // Start is_builtin/3
  "is_builtin/3": (module, fun, arity) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    if (!Type.isInteger(arity)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    // Check if it's a built-in function (BIF)
    // In Hologram, we'll check if it exists in the Erlang module
    const key = `${fun.value}/${arity.value}`;
    const exists = Erlang.hasOwnProperty(key);
    return Type.boolean(exists);
  },
  // End is_builtin/3
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

  // Start link/1
  "link/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // In Hologram, linking is simplified
    // Just return true to indicate success
    return Type.boolean(true);
  },
  // End link/1
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

  // Start list_to_atom/2
  "list_to_atom/2": (list, encoding) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isAtom(encoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Convert list to atom with encoding (for now ignore encoding)
    const segments = Type.listToArray(list).map((item) => {
      if (!Type.isInteger(item)) {
        throw new Error("List contains non-integer");
      }
      return Number(item.value);
    });

    const text = Bitstring.toText(Type.bitstring(segments));

    return Type.atom(text);
  },
  // End list_to_atom/2
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

  // Start list_to_existing_atom/2
  "list_to_existing_atom/2": (list, encoding) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isAtom(encoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // For now, ignore encoding and use list_to_existing_atom/1
    return Erlang["list_to_existing_atom/1"](list);
  },
  // End list_to_existing_atom/2
  // Deps: [:erlang.list_to_existing_atom/1]

  // Start list_to_binary/1
  "list_to_binary/1": (list) => {
    // list_to_binary is an alias for iolist_to_binary
    return Erlang["iolist_to_binary/1"](list);
  },
  // End list_to_binary/1
  // Deps: [:erlang.iolist_to_binary/1]

  // Start list_to_binary/2
  "list_to_binary/2": (list, encoding) => {
    if (!Type.isAtom(encoding)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Convert list to binary with encoding (for now ignore encoding)
    return Erlang["iolist_to_binary/1"](list);
  },
  // End list_to_binary/2
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

  // Start list_to_float/2
  "list_to_float/2": (list, options) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Convert list to float with options (for now ignore options)
    const codePoints = Type.listToArray(list).map((item) => {
      if (!Type.isInteger(item)) {
        throw new Error("List contains non-integer");
      }
      return Number(item.value);
    });

    const text = String.fromCharCode(...codePoints);
    const value = parseFloat(text);

    if (isNaN(value)) {
      throw new Error("not a valid float");
    }

    return Type.float(value);
  },
  // End list_to_float/2
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

  // Start list_to_integer/2
  "list_to_integer/2": (list, base) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
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
        Interpreter.buildArgumentErrorMsg(2, "not in range 2..36"),
      );
    }

    // Convert list of character codes to integer with specified base
    const codePoints = Type.listToArray(list).map((item) => {
      if (!Type.isInteger(item)) {
        throw new Error("List contains non-integer");
      }
      return Number(item.value);
    });

    const text = String.fromCharCode(...codePoints);
    return Type.integer(BigInt(parseInt(text, baseNum)));
  },
  // End list_to_integer/2
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

  // Start load_nif/2
  "load_nif/2": (path, loadInfo) => {
    if (!Type.isBitstring(path) && !Type.isList(path)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a string or charlist"),
      );
    }

    // Load a Native Implemented Function (NIF) library
    // In Hologram (browser environment), NIFs are not supported
    Interpreter.raiseHologramInterpreterError(
      "load_nif/2 is not supported in browser environment",
    );
  },
  // End load_nif/2
  // Deps: []

  // Start localtime_to_universaltime/1
  "localtime_to_universaltime/1": (localtime) => {
    if (!Type.isTuple(localtime) || localtime.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid datetime tuple"),
      );
    }

    // Convert local time to UTC
    // This is a simplified implementation - true conversion requires timezone info
    // For now, assume the local time is UTC
    return localtime;
  },
  // End localtime_to_universaltime/1
  // Deps: []

  // Start localtime_to_universaltime/2
  "localtime_to_universaltime/2": (localtime, isdst) => {
    if (!Type.isTuple(localtime) || localtime.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid datetime tuple"),
      );
    }

    if (!Type.isBoolean(isdst) && !Type.isAtom(isdst)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean or atom"),
      );
    }

    // Convert local time to UTC considering DST
    // This is a simplified implementation
    return localtime;
  },
  // End localtime_to_universaltime/2
  // Deps: []

  // Start load_module/2
  "load_module/2": (module, binary) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isBitstring(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a bitstring"),
      );
    }

    // Load a module from binary code
    // In Hologram (browser environment), we can't dynamically load compiled BEAM code
    Interpreter.raiseHologramInterpreterError(
      "load_module/2 is not supported in browser environment",
    );
  },
  // End load_module/2
  // Deps: []

  // Start loaded/0
  "loaded/0": () => {
    // Return list of loaded modules (simplified in Hologram)
    return Type.list([Type.atom("Erlang")]);
  },
  // End loaded/0
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

  // Start make_tuple/3
  "make_tuple/3": (size, initialValue, initList) => {
    if (!Type.isInteger(size)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isList(initList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Create tuple with default values
    const sizeNum = Number(size.value);
    const data = new Array(sizeNum).fill(initialValue);

    // Apply initial values from list
    let current = initList;
    while (Type.isList(current) && current.data.length > 0) {
      const item = current.data[0];
      if (Type.isTuple(item) && item.data.length === 2) {
        const index = item.data[0];
        const value = item.data[1];
        if (Type.isInteger(index)) {
          const idx = Number(index.value) - 1; // Convert to 0-based
          if (idx >= 0 && idx < sizeNum) {
            data[idx] = value;
          }
        }
      }
      current = current.data[1] || Type.list([]);
    }

    return Type.tuple(data);
  },
  // End make_tuple/3
  // Deps: []

  // Start md5_init/0
  "md5_init/0": () => {
    // Initialize MD5 context
    // In Hologram, we'll create a simple context object
    // Real MD5 would require a full implementation
    return Type.bitstring("md5_context_placeholder");
  },
  // End md5_init/0
  // Deps: []

  // Start md5_update/2
  "md5_update/2": (context, data) => {
    if (!Type.isBitstring(context)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid MD5 context"),
      );
    }

    if (!Type.isBitstring(data)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a bitstring"),
      );
    }

    // Update MD5 context with data
    // In Hologram, return a modified context (simplified)
    return Type.bitstring(context.value + "_" + data.value);
  },
  // End md5_update/2
  // Deps: []

  // Start md5_final/1
  "md5_final/1": (context) => {
    if (!Type.isBitstring(context)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid MD5 context"),
      );
    }

    // Finalize MD5 and return hash
    // In Hologram, we can't compute real MD5 without crypto library
    // Return a placeholder binary (real MD5 is 16 bytes)
    const placeholder = new Uint8Array(16);
    return Type.binary(placeholder);
  },
  // End md5_final/1
  // Deps: []

  // Start memory/0
  "memory/0": () => {
    // Return memory information (simplified in Hologram)
    const info = [
      Type.tuple([Type.atom("total"), Type.integer(0n)]),
      Type.tuple([Type.atom("processes"), Type.integer(0n)]),
      Type.tuple([Type.atom("system"), Type.integer(0n)]),
    ];
    return Type.list(info);
  },
  // End memory/0
  // Deps: []

  // Start memory/1
  "memory/1": (type) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Return memory information for specific type
    // Valid types: total, processes, processes_used, system, atom, atom_used, binary, code, ets
    const typeStr = type.value;
    const validTypes = [
      "total",
      "processes",
      "processes_used",
      "system",
      "atom",
      "atom_used",
      "binary",
      "code",
      "ets",
    ];

    if (!validTypes.includes(typeStr)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid memory type"),
      );
    }

    // In Hologram, return placeholder values
    return Type.integer(0n);
  },
  // End memory/1
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

  // Start module_loaded/1
  "module_loaded/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // In Hologram, we can't check loaded modules in the same way as Erlang
    // Return true for common modules, false otherwise
    const commonModules = ["Elixir.Kernel", "Elixir.Enum", "Elixir.List", "Elixir.String"];
    const isLoaded = commonModules.includes(module.value);
    return Type.boolean(isLoaded);
  },
  // End module_loaded/1
  // Deps: []

  // Start module_info/0
  "module_info/0": () => {
    // Get module information for current module
    // In Hologram, return a minimal module info list
    return Type.list([
      Type.tuple([Type.atom("module"), Type.atom("erlang")]),
      Type.tuple([Type.atom("attributes"), Type.list([])]),
      Type.tuple([Type.atom("exports"), Type.list([])]),
    ]);
  },
  // End module_info/0
  // Deps: []

  // Start module_info/1
  "module_info/1": (item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Get specific module information
    // Valid items: module, attributes, compile, exports, functions, nifs, native
    const itemStr = item.value;

    switch (itemStr) {
      case "module":
        return Type.atom("erlang");
      case "attributes":
      case "exports":
      case "functions":
      case "nifs":
        return Type.list([]);
      default:
        return Type.atom("undefined");
    }
  },
  // End module_info/1
  // Deps: []

  // Start get_module_info/1
  "get_module_info/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Get module information
    return Type.list([
      Type.tuple([Type.atom("module"), module]),
      Type.tuple([Type.atom("attributes"), Type.list([])]),
      Type.tuple([Type.atom("exports"), Type.list([])]),
    ]);
  },
  // End get_module_info/1
  // Deps: []

  // Start get_module_info/2
  "get_module_info/2": (module, item) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Get specific module information
    const itemStr = item.value;

    switch (itemStr) {
      case "module":
        return module;
      case "attributes":
      case "exports":
      case "functions":
      case "nifs":
        return Type.list([]);
      default:
        return Type.atom("undefined");
    }
  },
  // End get_module_info/2
  // Deps: []

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

  // Start monotonic_time/1
  "monotonic_time/1": (unit) => {
    if (!Type.isAtom(unit)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Get monotonic time in nanoseconds
    const timeMs = performance.now();
    const timeNs = BigInt(Math.floor(timeMs * 1_000_000));

    // Convert to requested unit
    const result = Erlang["convert_time_unit/3"](
      Type.integer(timeNs),
      Type.atom("nanosecond"),
      unit
    );

    return result;
  },
  // End monotonic_time/1
  // Deps: [:erlang.convert_time_unit/3]

  // Start monitor/2
  "monitor/2": (type, item) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (type.value !== "process") {
      Interpreter.raiseArgumentError(
        "invalid monitor type, only 'process' is supported",
      );
    }

    // Return a reference for the monitor
    return Erlang["make_ref/0"]();
  },
  // End monitor/2
  // Deps: [:erlang.make_ref/0]

  // Start monitor/3
  "monitor/3": (type, item, options) => {
    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Set up a monitor with options
    // Options can include: {alias, Alias}, {tag, Tag}
    // In Hologram, monitoring is simplified
    return Erlang["make_ref/0"]();
  },
  // End monitor/3
  // Deps: [:erlang.make_ref/0]

  // Start monitor_node/2
  "monitor_node/2": (node, flag) => {
    if (!Type.isAtom(node)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isBoolean(flag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    // Monitor a node for connectivity
    // In Hologram (browser environment), we don't have distributed nodes
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End monitor_node/2
  // Deps: []

  // Start open_port/2
  "open_port/2": (portName, portSettings) => {
    if (!Type.isTuple(portName) && !Type.isAtom(portName)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple or atom"),
      );
    }

    if (!Type.isList(portSettings)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Open a port for communication with external programs
    // In Hologram (browser environment), we can't open real ports
    Interpreter.raiseHologramInterpreterError(
      "open_port/2 is not supported in browser environment",
    );
  },
  // End open_port/2
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

  // Start node/1
  "node/1": (arg) => {
    // Return the node of pid/port/reference
    // In Hologram, everything is on the same node
    return Type.atom("nonode@nohost");
  },
  // End node/1
  // Deps: []

  // Start nif_error/1
  "nif_error/1": (reason) => {
    // Raise a NIF error
    // This is used by NIF stubs to indicate the NIF wasn't loaded
    Interpreter.raiseArgumentError("NIF library not loaded: " + reason);
  },
  // End nif_error/1
  // Deps: []

  // Start nif_error/2
  "nif_error/2": (reason, args) => {
    if (!Type.isList(args)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Raise a NIF error with arguments
    Interpreter.raiseArgumentError("NIF library not loaded: " + reason);
  },
  // End nif_error/2
  // Deps: []

  // Start now/0
  "now/0": () => {
    // Return timestamp as {MegaSecs, Secs, MicroSecs} (deprecated but still used)
    // This is similar to timestamp/0
    return Erlang["timestamp/0"]();
  },
  // End now/0
  // Deps: [:erlang.timestamp/0]

  // Start nodes/0
  "nodes/0": () => {
    // Return list of connected nodes (empty in Hologram)
    return Type.list([]);
  },
  // End nodes/0
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
  "or/2": (boolean1, boolean2) => {
    if (!Type.isBoolean(boolean1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(boolean2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    // Logical OR operation
    return Type.boolean(boolean1.value || boolean2.value);
  },
  // End or/2
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

  // Start purge_module/1
  "purge_module/1": (module) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Purge old code for module
    // In Hologram, modules are not dynamically loaded/unloaded
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End purge_module/1
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

  // Start pid_to_binary/1
  "pid_to_binary/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // Convert PID to binary
    return Type.bitstring(pid.value);
  },
  // End pid_to_binary/1
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

  // Start port_to_binary/1
  "port_to_binary/1": (port) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    // Convert port to binary
    return Type.bitstring(port.value);
  },
  // End port_to_binary/1
  // Deps: []

  // Start port_call/3
  "port_call/3": (port, operation, data) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    if (!Type.isInteger(operation)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Synchronous call to port
    // In Hologram (browser environment), ports are not supported
    Interpreter.raiseHologramInterpreterError(
      "port_call/3 is not supported in browser environment",
    );
  },
  // End port_call/3
  // Deps: []

  // Start port_close/1
  "port_close/1": (port) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    // Close a port
    // In Hologram (browser environment), ports are not supported
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End port_close/1
  // Deps: []

  // Start port_command/2
  "port_command/2": (port, data) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    // Send data to port
    // In Hologram (browser environment), ports are not supported
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End port_command/2
  // Deps: []

  // Start port_command/3
  "port_command/3": (port, data, options) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Send data to port with options
    // Options can include: force, nosuspend
    // In Hologram (browser environment), ports are not supported
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End port_command/3
  // Deps: []

  // Start port_connect/2
  "port_connect/2": (port, pid) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a pid"),
      );
    }

    // Connect port to a new controlling process
    // In Hologram (browser environment), ports are not supported
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End port_connect/2
  // Deps: []

  // Start port_info/1
  "port_info/1": (port) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    // Get information about a port
    // In Hologram (browser environment), ports are not supported
    // Return a minimal info list
    return Type.list([
      Type.tuple([Type.atom("name"), Type.bitstring("hologram_port")]),
      Type.tuple([Type.atom("connected"), Type.pid("<0.0.0>")]),
    ]);
  },
  // End port_info/1
  // Deps: []

  // Start port_info/2
  "port_info/2": (port, item) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Get specific information about a port
    // Valid items: registered_name, id, connected, links, name, input, output, etc.
    // In Hologram, return placeholder values
    const itemStr = item.value;

    switch (itemStr) {
      case "name":
        return Type.tuple([Type.atom("name"), Type.bitstring("hologram_port")]);
      case "connected":
        return Type.tuple([Type.atom("connected"), Type.pid("<0.0.0>")]);
      case "id":
        return Type.tuple([Type.atom("id"), Type.integer(0n)]);
      default:
        return Type.atom("undefined");
    }
  },
  // End port_info/2
  // Deps: []

  // Start ports/0
  "ports/0": () => {
    // Return list of all ports in the system
    // In Hologram, we don't have real ports, so return empty list
    return Type.list([]);
  },
  // End ports/0
  // Deps: []

  // Start port_control/3
  "port_control/3": (port, operation, data) => {
    if (!Type.isPort(port)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a port"),
      );
    }

    if (!Type.isInteger(operation)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    // Port control is not supported in browser environment
    throw new HologramInterpreterError(
      "Function :erlang.port_control/3 is not supported in Hologram.\n" +
      "Port operations are not available in a browser environment.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End port_control/3
  // Deps: []

  // Start phash/2
  "phash/2": (term, range) => {
    if (!Type.isInteger(range)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const rangeNum = Number(range.value);
    if (rangeNum < 1) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "range must be at least 1"),
      );
    }

    // Simple hash function (deprecated in favor of phash2)
    // Use same algorithm as hash/2
    const str = Interpreter.inspect(term);
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }

    // Return hash in range [1, range]
    const result = (Math.abs(hash) % rangeNum) + 1;
    return Type.integer(BigInt(result));
  },
  // End phash/2
  // Deps: []

  // Start phash/1
  "phash/1": (term) => {
    // Portable hash function (deprecated, use phash2 instead)
    // Default range is 2^27
    return Erlang["phash/2"](term, Type.integer(BigInt(134217728)));
  },
  // End phash/1
  // Deps: [:erlang.phash/2]

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

  // Start phash2/3
  "phash2/3": (term, range, _seed) => {
    // Note: Erlang phash2/3 doesn't exist, it's phash2/2
    // But implementing for completeness with 3-arg version that ignores seed
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

    // Use phash2/2 and ignore the seed parameter
    return Erlang["phash2/2"](term, range);
  },
  // End phash2/3
  // Deps: [:erlang.phash2/2]

  // Start pre_loaded/0
  "pre_loaded/0": () => {
    // Return list of preloaded modules
    // In standard Erlang, these are modules loaded at startup
    // For Hologram, return a minimal set
    return Type.list([
      Type.atom("erlang"),
      Type.atom("init"),
      Type.atom("prim_file"),
      Type.atom("prim_inet"),
      Type.atom("prim_zip"),
      Type.atom("zlib"),
    ]);
  },
  // End pre_loaded/0
  // Deps: []

  // Start processes/0
  "processes/0": () => {
    // In Hologram, return a list with just the current process
    // Full implementation would require process tracking
    return Type.list([Type.pid("<0.0.0>")]);
  },
  // End processes/0
  // Deps: []

  // Start process_flag/2
  "process_flag/2": (flag, value) => {
    if (!Type.isAtom(flag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // In Hologram, return default values for process flags
    return Type.atom("undefined");
  },
  // End process_flag/2
  // Deps: []

  // Start process_info/1
  "process_info/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // Return basic process info
    const info = [
      Type.tuple([Type.atom("status"), Type.atom("running")]),
      Type.tuple([Type.atom("messages"), Type.list([])]),
    ];

    return Type.list(info);
  },
  // End process_info/1
  // Deps: []

  // Start process_info/2
  "process_info/2": (pid, item) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const itemName = item.value;

    switch (itemName) {
      case "status":
        return Type.tuple([Type.atom("status"), Type.atom("running")]);
      case "messages":
        return Type.tuple([Type.atom("messages"), Type.list([])]);
      default:
        return Type.atom("undefined");
    }
  },
  // End process_info/2
  // Deps: []

  // Start process_display/2
  "process_display/2": (pid, type) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isAtom(type)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Display process info (in browser, just log to console)
    console.log(`Process ${pid.value}: ${type.value}`);
    return Type.boolean(true);
  },
  // End process_display/2
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

  // Start resume_process/1
  "resume_process/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // Resume a suspended process
    // In Hologram (browser environment), we don't have true process suspension
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End resume_process/1
  // Deps: []

  // Start resume_process/2
  "resume_process/2": (pid, optionList) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isList(optionList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Resume a suspended process with options
    // Options can include: asynchronous, synchronous
    // In Hologram (browser environment), we don't have true process suspension
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End resume_process/2
  // Deps: []

  // Start read_timer/1
  "read_timer/1": (timerRef) => {
    if (!Type.isReference(timerRef)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    // Check if timer exists in global timer registry
    if (!globalThis.__hologramTimers) {
      globalThis.__hologramTimers = {};
    }

    const timerId = timerRef.value;
    if (globalThis.__hologramTimers[timerId]) {
      const remaining = globalThis.__hologramTimers[timerId].remaining;
      return Type.integer(BigInt(Math.max(0, remaining)));
    }

    return Type.boolean(false);
  },
  // End read_timer/1
  // Deps: []

  // Start raise/3
  "raise/3": (classAtom, reason, stacktrace) => {
    if (!Type.isAtom(classAtom)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isList(stacktrace)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Raise an exception of the given class with reason and stacktrace
    // Valid classes: error, exit, throw
    const classStr = classAtom.value;
    if (!["error", "exit", "throw"].includes(classStr)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid exception class"),
      );
    }

    // Create and throw a boxed error with the reason
    // The stacktrace is provided but we'll use it for context
    throw Interpreter.buildHologramBoxedError(reason);
  },
  // End raise/3
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

  // Start ref_to_binary/1
  "ref_to_binary/1": (ref) => {
    if (!Type.isReference(ref)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    // Convert reference to binary
    return Type.bitstring(ref.value);
  },
  // End ref_to_binary/1
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

  // Start send_after/3
  "send_after/3": (time, dest, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isPid(dest) && !Type.isAtom(dest)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a pid or atom"),
      );
    }

    // Create a timer reference
    const timerRef = Type.reference();
    const timeMs = Number(time.value);

    // Initialize timer registry
    if (!globalThis.__hologramTimers) {
      globalThis.__hologramTimers = {};
    }

    // Set up the timer
    const startTime = Date.now();
    const timeoutId = setTimeout(() => {
      // In a real implementation, this would send the message to the process
      // For now, just clean up the timer
      delete globalThis.__hologramTimers[timerRef.value];
    }, timeMs);

    // Store timer info
    globalThis.__hologramTimers[timerRef.value] = {
      timeoutId,
      remaining: timeMs,
      startTime,
    };

    return timerRef;
  },
  // End send_after/3
  // Deps: []

  // Start send_nosuspend/2
  "send_nosuspend/2": (dest, message) => {
    if (!Type.isPid(dest) && !Type.isAtom(dest)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or atom"),
      );
    }

    // Send without suspending if port busy
    // In Hologram, just return true (message sent)
    return Type.boolean(true);
  },
  // End send_nosuspend/2
  // Deps: []

  // Start send_nosuspend/3
  "send_nosuspend/3": (dest, msg, options) => {
    if (!Type.isPid(dest) && !Type.isPort(dest) && !Type.isAtom(dest)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a pid, port, or registered name",
        ),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Send message without suspending if destination busy
    // Options can include: noconnect, nosuspend
    // In Hologram, just return true (message sent)
    return Type.boolean(true);
  },
  // End send_nosuspend/3
  // Deps: []

  // Start set_cookie/2
  "set_cookie/2": (node, cookie) => {
    if (!Type.isAtom(node)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    if (!Type.isAtom(cookie)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Set magic cookie for distributed Erlang
    // In Hologram, this is a no-op since we don't have distributed nodes
    return Type.boolean(true);
  },
  // End set_cookie/2
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

  // Start spawn_link/1
  "spawn_link/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Create a new process (simulated with a unique PID)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    const newPid = Type.pid("client", [0, timestamp, random], "client");

    // In a real implementation, this would create a linked process
    // For now, we just return the PID
    return newPid;
  },
  // End spawn_link/1
  // Deps: []

  // Start spawn_link/3
  "spawn_link/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
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

    // Return a unique PID (using timestamp and random number)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    return Type.pid("client", [0, timestamp, random], "client");
  },
  // End spawn_link/3
  // Deps: []

  // Start spawn_monitor/1
  "spawn_monitor/1": (fun) => {
    if (!Type.isFunction(fun)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a function"),
      );
    }

    // Create a new process (simulated with a unique PID)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    const newPid = Type.pid("client", [0, timestamp, random], "client");

    // Create a monitor reference
    const monitorRef = Type.reference();

    // Return tuple of {pid, reference}
    return Type.tuple([newPid, monitorRef]);
  },
  // End spawn_monitor/1
  // Deps: []

  // Start spawn_monitor/3
  "spawn_monitor/3": (module, fun, args) => {
    if (!Type.isAtom(module)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
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

    // Create a new process (simulated with a unique PID)
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000000);
    const newPid = Type.pid("client", [0, timestamp, random], "client");

    // Create a monitor reference
    const monitorRef = Type.reference();

    // Return tuple of {pid, reference}
    return Type.tuple([newPid, monitorRef]);
  },
  // End spawn_monitor/3
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

  // Start start_timer/3
  "start_timer/3": (time, dest, message) => {
    if (!Type.isInteger(time)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an integer"),
      );
    }

    if (!Type.isPid(dest) && !Type.isAtom(dest)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a pid or atom"),
      );
    }

    // Create a timer reference
    const timerRef = Type.reference();
    const timeMs = Number(time.value);

    // Initialize timer registry
    if (!globalThis.__hologramTimers) {
      globalThis.__hologramTimers = {};
    }

    // Set up the timer
    const startTime = Date.now();
    const timeoutId = setTimeout(() => {
      // In a real implementation, this would send {timeout, Ref, Msg} to the process
      // For now, just clean up the timer
      delete globalThis.__hologramTimers[timerRef.value];
    }, timeMs);

    // Store timer info
    globalThis.__hologramTimers[timerRef.value] = {
      timeoutId,
      remaining: timeMs,
      startTime,
    };

    return timerRef;
  },
  // End start_timer/3
  // Deps: []

  // Start statistics/1
  "statistics/1": (item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    const itemName = item.value;

    switch (itemName) {
      case "runtime":
        // Return {TotalRunTime, TimeSinceLastCall} in milliseconds
        const now = Date.now();
        if (!globalThis.__hologramStatsRuntime) {
          globalThis.__hologramStatsRuntime = { start: now, last: now };
        }
        const total = now - globalThis.__hologramStatsRuntime.start;
        const since = now - globalThis.__hologramStatsRuntime.last;
        globalThis.__hologramStatsRuntime.last = now;
        return Type.tuple([Type.integer(BigInt(total)), Type.integer(BigInt(since))]);

      case "wall_clock":
        // Similar to runtime but for wall clock time
        const wallNow = Date.now();
        if (!globalThis.__hologramStatsWallClock) {
          globalThis.__hologramStatsWallClock = { start: wallNow, last: wallNow };
        }
        const wallTotal = wallNow - globalThis.__hologramStatsWallClock.start;
        const wallSince = wallNow - globalThis.__hologramStatsWallClock.last;
        globalThis.__hologramStatsWallClock.last = wallNow;
        return Type.tuple([Type.integer(BigInt(wallTotal)), Type.integer(BigInt(wallSince))]);

      case "reductions":
        // Return {TotalReductions, ReductionsSinceLastCall}
        return Type.tuple([Type.integer(0n), Type.integer(0n)]);

      default:
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "unsupported statistics item"),
        );
    }
  },
  // End statistics/1
  // Deps: []

  // Start system_flag/2
  "system_flag/2": (flag, value) => {
    if (!Type.isAtom(flag)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // In Hologram, we can't actually set system flags
    // Just return the "old" value (which is always the same as the new value)
    // Common flags: backtrace_depth, cpu_topology, dirty_cpu_schedulers_online, etc.
    return value;
  },
  // End system_flag/2
  // Deps: []

  // Start system_monitor/0
  "system_monitor/0": () => {
    // Get current system monitor settings
    // Returns {MonitorPid, Options} or undefined
    // In Hologram, return undefined (no monitoring set)
    return Type.atom("undefined");
  },
  // End system_monitor/0
  // Deps: []

  // Start system_monitor/1
  "system_monitor/1": (arg) => {
    if (!Type.isPid(arg) && !Type.isAtom(arg)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or atom"),
      );
    }

    // Set or clear system monitor
    // In Hologram (browser environment), system monitoring is not supported
    // Return previous settings (undefined)
    return Type.atom("undefined");
  },
  // End system_monitor/1
  // Deps: []

  // Start system_monitor/2
  "system_monitor/2": (monitorPid, options) => {
    if (!Type.isPid(monitorPid) && !Type.isAtom(monitorPid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or atom"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Set system monitor with options
    // Options can include: busy_port, busy_dist_port, long_gc, long_schedule, etc.
    // In Hologram, return undefined (no previous monitor)
    return Type.atom("undefined");
  },
  // End system_monitor/2
  // Deps: []

  // Start system_profile/0
  "system_profile/0": () => {
    // Get current system profiler settings
    // Returns {ProfilerPid, Options} or undefined
    // In Hologram, return undefined (no profiling)
    return Type.atom("undefined");
  },
  // End system_profile/0
  // Deps: []

  // Start system_profile/1
  "system_profile/1": (arg) => {
    if (!Type.isPid(arg) && !Type.isPort(arg) && !Type.isAtom(arg)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a pid, port, or atom",
        ),
      );
    }

    // Set or clear system profiler
    // In Hologram (browser environment), profiling is not supported
    return Type.atom("undefined");
  },
  // End system_profile/1
  // Deps: []

  // Start system_profile/2
  "system_profile/2": (profilerPid, options) => {
    if (!Type.isPid(profilerPid) && !Type.isPort(profilerPid) && !Type.isAtom(profilerPid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a pid, port, or atom",
        ),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Set system profiler with options
    // Options can include: runnable_procs, runnable_ports, scheduler, timestamp, etc.
    // In Hologram, return undefined (no previous profiler)
    return Type.atom("undefined");
  },
  // End system_profile/2
  // Deps: []

  // Start system_info/1
  "system_info/1": (item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    const itemName = item.value;

    switch (itemName) {
      case "process_count":
        return Type.integer(1n);
      case "port_count":
        return Type.integer(0n);
      case "system_version":
        return Type.bitstring("Hologram 0.1.0");
      case "otp_release":
        return Type.bitstring("27");
      case "wordsize":
        return Type.integer(8n);
      default:
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "unsupported system_info item"),
        );
    }
  },
  // End system_info/1
  // Deps: []

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

  // Start system_time/1
  "system_time/1": (unit) => {
    if (!Type.isAtom(unit)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not an atom"),
      );
    }

    // Get system time in nanoseconds
    const timeMs = Date.now();
    const timeNs = BigInt(timeMs) * 1_000_000n;

    // Convert to requested unit
    const result = Erlang["convert_time_unit/3"](
      Type.integer(timeNs),
      Type.atom("nanosecond"),
      unit
    );

    return result;
  },
  // End system_time/1
  // Deps: [:erlang.convert_time_unit/3]

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

  // Start term_to_binary/2
  "term_to_binary/2": (term, options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Serialize Erlang term to binary with options
    // Options can include: compressed, {compressed, Level}, {minor_version, Version}
    // In Hologram (browser environment), we can't serialize to External Term Format
    Interpreter.raiseHologramInterpreterError(
      "Serializing to Erlang External Term Format requires complex binary encoding.\n" +
      "See what to do here: https://www.hologram.page/TODO"
    );
  },
  // End term_to_binary/2
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

  // Start trace/3
  "trace/3": (pidPortSpec, how, flagList) => {
    if (!Type.isList(flagList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Enable/disable tracing for processes or ports
    // In Hologram (browser environment), tracing is not supported
    // Return the number of processes/ports affected (0)
    return Type.integer(0n);
  },
  // End trace/3
  // Deps: []

  // Start trace_delivered/1
  "trace_delivered/1": (tracee) => {
    if (!Type.isPid(tracee) && !Type.isAtom(tracee)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or atom"),
      );
    }

    // Get trace message delivery reference
    // In Hologram, tracing is not supported
    return Erlang["make_ref/0"]();
  },
  // End trace_delivered/1
  // Deps: [:erlang.make_ref/0]

  // Start trace_info/2
  "trace_info/2": (pidPortFuncEvent, item) => {
    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    // Get trace information
    // In Hologram, tracing is not supported
    return Type.atom("undefined");
  },
  // End trace_info/2
  // Deps: []

  // Start trace_pattern/2
  "trace_pattern/2": (mfa, matchSpec) => {
    // Set trace patterns for function calls
    // In Hologram (browser environment), tracing is not supported
    // Return the number of functions that matched (0)
    return Type.integer(0n);
  },
  // End trace_pattern/2
  // Deps: []

  // Start trace_pattern/3
  "trace_pattern/3": (mfa, matchSpec, flagList) => {
    if (!Type.isList(flagList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Set trace patterns with flags
    // Flags can include: global, local, meta, call_count, call_time
    // In Hologram, tracing is not supported
    return Type.integer(0n);
  },
  // End trace_pattern/3
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

  // Start unlink/1
  "unlink/1": (pid) => {
    if (!Type.isPid(pid) && !Type.isPort(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid or port"),
      );
    }

    // In a real implementation, this would remove the link to the process
    // For now, we just return true
    return Type.boolean(true);
  },
  // End unlink/1
  // Deps: []

  // Start unalias/1
  "unalias/1": (alias) => {
    if (!Type.isReference(alias)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a reference"),
      );
    }

    // Deactivate an alias
    // In Hologram, aliases are simplified
    return Type.boolean(true);
  },
  // End unalias/1
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

  // Start universaltime_to_localtime/1
  "universaltime_to_localtime/1": (universaltime) => {
    if (!Type.isTuple(universaltime)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a tuple"),
      );
    }

    // Convert UTC time to local time
    // universaltime is {{Year, Month, Day}, {Hour, Minute, Second}}
    // This is a simplified implementation that just returns the same time
    // A full implementation would adjust for timezone
    return universaltime;
  },
  // End universaltime_to_localtime/1
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

  // Start xor/2
  "xor/2": (boolean1, boolean2) => {
    if (!Type.isBoolean(boolean1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a boolean"),
      );
    }

    if (!Type.isBoolean(boolean2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a boolean"),
      );
    }

    // Logical XOR operation
    const result = boolean1.value !== boolean2.value;
    return Type.boolean(result);
  },
  // End xor/2
  // Deps: []

  // Start subtract/2
  "subtract/2": (list1, list2) => {
    if (!Type.isList(list1)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    if (!Type.isList(list2)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Subtract list2 from list1 (remove first occurrence of each element)
    // This is the same as list1 -- list2
    return Erlang["--/2"](list1, list2);
  },
  // End subtract/2
  // Deps: [:erlang.--/2]

  // Start suspend_process/1
  "suspend_process/1": (pid) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    // Suspend a process
    // In Hologram (browser environment), we don't have true process suspension
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End suspend_process/1
  // Deps: []

  // Start suspend_process/2
  "suspend_process/2": (pid, optionList) => {
    if (!Type.isPid(pid)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a pid"),
      );
    }

    if (!Type.isList(optionList)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Suspend a process with options
    // Options can include: asynchronous, unless_suspending
    // In Hologram (browser environment), we don't have true process suspension
    // Just return true indicating success
    return Type.boolean(true);
  },
  // End suspend_process/2
  // Deps: []

  // Start yield/0
  "yield/0": () => {
    // Yield voluntarily to allow other processes to run
    // In a browser environment, we can't actually yield to other Erlang processes
    // Return true to indicate the process is still running
    return Type.boolean(true);
  },
  // End yield/0
  // Deps: []
};

export default Erlang;
