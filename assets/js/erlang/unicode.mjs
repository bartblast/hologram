"use strict";

import Bitstring from "../bitstring.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Unicode = {
  // Start characters_to_binary/1
  "characters_to_binary/1": (input) => {
    const encoding = Type.atom("utf8");
    return Erlang_Unicode["characters_to_binary/3"](input, encoding, encoding);
  },
  // End characters_to_binary/1
  // Deps: [:unicode.characters_to_binary/3]

  // Start characters_to_binary/3
  "characters_to_binary/3": (input, inputEncoding, outputEncoding) => {
    // TODO: implement inputEncoding and outputEncoding arguments validation

    // TODO: implement other encodings for inputEncoding param
    if (!Interpreter.isStrictlyEqual(inputEncoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    // TODO: implement other encodings for outputEncoding param
    if (!Interpreter.isStrictlyEqual(outputEncoding, Type.atom("utf8"))) {
      throw new HologramInterpreterError(
        "encodings other than utf8 are not yet implemented in Hologram",
      );
    }

    if (Type.isBinary(input)) {
      return input;
    }

    if (!Type.isList(input)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not valid character data (an iodata term)",
        ),
      );
    }

    const flatInput = Erlang_Lists["flatten/1"](input);
    const chunks = [];

    for (let i = 0; i < flatInput.data.length; ++i) {
      const elem = flatInput.data[i];

      if (Type.isBinary(elem)) {
        chunks.push(elem);
      } else if (Type.isInteger(elem)) {
        if (Bitstring.validateCodePoint(elem.value)) {
          const segment = Type.bitstringSegment(elem, {type: "utf8"});
          chunks.push(Bitstring.fromSegments([segment]));
        } else {
          const remainingElems = flatInput.data.slice(i);

          return Type.tuple([
            Type.atom("error"),
            Bitstring.concat(chunks),
            Type.list(remainingElems),
          ]);
        }
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    }

    return Bitstring.concat(chunks);
  },
  // End characters_to_binary/3
  // Deps: [:lists.flatten/1]

  // TODO: finish porting (at the moment only UTF8 binary input is accepted)
  // Start characters_to_list/1
  "characters_to_list/1": (data) => {
    let isValidArg = true;

    if (Type.isList(data)) {
      isValidArg = data.data.every((item) => Bitstring.isText(item));
    } else {
      isValidArg = Bitstring.isText(data);
    }

    if (!isValidArg) {
      throw new HologramInterpreterError(
        "Function :unicode.characters_to_list/1 is not yet fully ported and at the moment accepts only UTF8 binary input.\n" +
          `The following input was received: ${Interpreter.inspect(data)}\n` +
          "See what to do here: https://www.hologram.page/TODO",
      );
    }

    let bitstring;

    if (Type.isList(data)) {
      bitstring = Bitstring.concat(data.data);
    } else {
      bitstring = data;
    }

    return Bitstring.toCodepoints(bitstring);
  },
  // End characters_to_list/1
  // Deps: []

  // Start characters_to_nfc_binary/1
  "characters_to_nfc_binary/1": (input) => {
    let str;

    if (Type.isBinary(input)) {
      Bitstring.maybeSetBytesFromText(input);
      str = new TextDecoder("utf-8").decode(input.bytes);
    } else if (Type.isList(input)) {
      const chars = input.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "not valid character data"),
          );
        }
        return String.fromCharCode(Number(elem.value));
      });
      str = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or list"),
      );
    }

    // Normalize to NFC (Canonical Decomposition, followed by Canonical Composition)
    const normalized = str.normalize("NFC");
    const bytes = new TextEncoder().encode(normalized);

    return Type.bitstring(bytes, 0);
  },
  // End characters_to_nfc_binary/1
  // Deps: []

  // Start characters_to_nfc_list/1
  "characters_to_nfc_list/1": (input) => {
    const binary = Erlang_Unicode["characters_to_nfc_binary/1"](input);
    const codepoints = Bitstring.toCodepoints(binary);
    return codepoints;
  },
  // End characters_to_nfc_list/1
  // Deps: [:unicode.characters_to_nfc_binary/1]

  // Start characters_to_nfd_binary/1
  "characters_to_nfd_binary/1": (input) => {
    let str;

    if (Type.isBinary(input)) {
      Bitstring.maybeSetBytesFromText(input);
      str = new TextDecoder("utf-8").decode(input.bytes);
    } else if (Type.isList(input)) {
      const chars = input.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "not valid character data"),
          );
        }
        return String.fromCharCode(Number(elem.value));
      });
      str = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or list"),
      );
    }

    // Normalize to NFD (Canonical Decomposition)
    const normalized = str.normalize("NFD");
    const bytes = new TextEncoder().encode(normalized);

    return Type.bitstring(bytes, 0);
  },
  // End characters_to_nfd_binary/1
  // Deps: []

  // Start characters_to_nfkc_binary/1
  "characters_to_nfkc_binary/1": (input) => {
    let str;

    if (Type.isBinary(input)) {
      Bitstring.maybeSetBytesFromText(input);
      str = new TextDecoder("utf-8").decode(input.bytes);
    } else if (Type.isList(input)) {
      const chars = input.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "not valid character data"),
          );
        }
        return String.fromCharCode(Number(elem.value));
      });
      str = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or list"),
      );
    }

    // Normalize to NFKC (Compatibility Decomposition, followed by Canonical Composition)
    const normalized = str.normalize("NFKC");
    const bytes = new TextEncoder().encode(normalized);

    return Type.bitstring(bytes, 0);
  },
  // End characters_to_nfkc_binary/1
  // Deps: []

  // Start characters_to_nfkd_binary/1
  "characters_to_nfkd_binary/1": (input) => {
    let str;

    if (Type.isBinary(input)) {
      Bitstring.maybeSetBytesFromText(input);
      str = new TextDecoder("utf-8").decode(input.bytes);
    } else if (Type.isList(input)) {
      const chars = input.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "not valid character data"),
          );
        }
        return String.fromCharCode(Number(elem.value));
      });
      str = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or list"),
      );
    }

    // Normalize to NFKD (Compatibility Decomposition)
    const normalized = str.normalize("NFKD");
    const bytes = new TextEncoder().encode(normalized);

    return Type.bitstring(bytes, 0);
  },
  // End characters_to_nfkd_binary/1
  // Deps: []
};

export default Erlang_Unicode;
