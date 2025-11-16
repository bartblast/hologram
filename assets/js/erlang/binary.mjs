"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

const Erlang_Binary = {
  // Start at/2
  "at/2": function (subject, pos) {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    if (!Type.isInteger(pos)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (pos.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);

    if (pos.value >= subject.bytes.length) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.integer(subject.bytes[pos.value]);
  },
  // End at/2
  // Deps: []

  // Start copy/2
  "copy/2": function (subject, count) {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    if (!Type.isInteger(count)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (count.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (count.value === 0n) {
      return Bitstring.fromText("");
    }

    if (count.value === 1n) {
      return subject;
    }

    const countNumber = Number(count.value);

    if (subject.text !== null) {
      return Bitstring.fromText(subject.text.repeat(countNumber));
    }

    if (subject.bytes.length === 0) {
      return Bitstring.fromText("");
    }

    const sourceBytes = subject.bytes;
    const sourceLength = sourceBytes.length;
    const totalLength = sourceLength * countNumber;
    const resultBytes = new Uint8Array(totalLength);

    for (let i = 0; i < countNumber; i++) {
      resultBytes.set(sourceBytes, i * sourceLength);
    }

    return Bitstring.fromBytes(resultBytes);
  },
  // End copy/2
  // Deps: []
};

export default Erlang_Binary;
