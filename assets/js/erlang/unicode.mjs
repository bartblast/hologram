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
          chunks.push(Bitstring.from([segment]));
        } else {
          const remainingElems = flatInput.data.slice(i);

          return Type.tuple([
            Type.atom("error"),
            Bitstring.merge(chunks),
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

    return Bitstring.merge(chunks);
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
      bitstring = Bitstring.merge(data.data);
    } else {
      bitstring = data;
    }

    let offset = 0;
    const codePoints = [];

    while (offset < bitstring.bits.length) {
      const codePointInfo = Bitstring.fetchNextCodePointFromUtf8BitstringChunk(
        bitstring.bits,
        offset,
      );

      codePoints.push(codePointInfo[0]);
      offset += codePointInfo[1];
    }

    return Type.list(codePoints);
  },
  // End characters_to_list/1
  // Deps: []
};

export default Erlang_Unicode;
