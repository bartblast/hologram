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
  "characters_to_nfc_binary/1": (data) => {
    // Helpers

    // Scans forward once to find the longest valid UTF-8 prefix.
    // Uses UTF-8 byte structure to validate incrementally: single-byte (0xxxxxxx),
    // multi-byte leaders (11xxxxxx), and continuation bytes (10xxxxxx).
    const findValidUtf8Length = (bytes) => {
      const getSequenceLength = (byte) => {
        if ((byte & 0x80) === 0) return 1;
        if ((byte & 0xe0) === 0xc0) return 2;
        if ((byte & 0xf0) === 0xe0) return 3;
        if ((byte & 0xf8) === 0xf0) return 4;
        return -1;
      };

      const isValidContinuation = (byte) => (byte & 0xc0) === 0x80;

      const isValidSequence = (start, length) => {
        if (start + length > bytes.length) return false;

        return Array.from({length: length - 1}, (_, i) => i + 1).every(
          (offset) => isValidContinuation(bytes[start + offset]),
        );
      };

      let pos = 0;
      while (pos < bytes.length) {
        const seqLength = getSequenceLength(bytes[pos]);
        if (seqLength === -1 || !isValidSequence(pos, seqLength)) break;
        pos += seqLength;
      }

      return pos;
    };

    // Validates that rest is a list containing a binary (from invalid UTF-8).
    // Raises ArgumentError if it's a list of invalid codepoints instead.
    const validateListRest = (rest) => {
      if (rest.data.length === 0 || !Type.isBinary(rest.data[0])) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            1,
            "not valid character data (an iodata term)",
          ),
        );
      }
    };

    // Handles error tuples from characters_to_binary/3.
    // Distinguishes between invalid codepoints (raises ArgumentError) and
    // invalid UTF-8 (returns error tuple with normalized prefix).
    const handleConversionError = (tag, prefix, rest) => {
      const textPrefix = Bitstring.toText(prefix);
      const normalizedPrefix =
        textPrefix === false
          ? prefix
          : Type.bitstring(textPrefix.normalize("NFC"));

      if (Type.isList(rest)) {
        validateListRest(rest);

        // rest.data[0] is the binary with invalid UTF-8
        return Type.tuple([tag, normalizedPrefix, rest.data[0]]);
      }

      return Type.tuple([tag, normalizedPrefix, rest]);
    };

    // Handles valid binary input with invalid UTF-8 bytes.
    // Finds the UTF-8 validity boundary, normalizes the valid prefix,
    // and returns error tuple with normalized prefix and invalid remainder.
    const handleInvalidUtf8 = (bytes) => {
      const validLength = findValidUtf8Length(bytes);
      const validPrefix = Bitstring.fromBytes(bytes.slice(0, validLength));
      const invalidRest = Bitstring.fromBytes(bytes.slice(validLength));
      const validText = Bitstring.toText(validPrefix);

      // Guard against validText being false (if validPrefix is somehow invalid UTF-8)
      const normalizedPrefix =
        validText === false
          ? Type.bitstring("")
          : Type.bitstring(validText.normalize("NFC"));

      return Type.tuple([Type.atom("error"), normalizedPrefix, invalidRest]);
    };

    // Main logic

    const utf8 = Type.atom("utf8");
    const converted = Erlang_Unicode["characters_to_binary/3"](
      data,
      utf8,
      utf8,
    );

    // characters_to_binary/3 returns either a binary (success) or error tuple
    if (Type.isTuple(converted)) {
      return handleConversionError(
        converted.data[0],
        converted.data[1],
        converted.data[2],
      );
    }

    // Valid binary - check for UTF-8 validity then normalize
    const text = Bitstring.toText(converted);
    if (text === false) return handleInvalidUtf8(converted.bytes);

    const normalized = text.normalize("NFC");

    return Type.bitstring(normalized);
  },
  // End characters_to_nfc_binary/1
  // Deps: [:unicode.characters_to_binary/3]
};

export default Erlang_Unicode;
