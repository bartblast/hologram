"use strict";

import Interpreter from "../interpreter.mjs";
import Utils from "../utils.mjs";
import Type from "../type.mjs";
import Bitstring from "../bitstring.mjs";
import Lists from "./lists.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const titlecase_unsupported_codepoints = [
  223, 452, 454, 455, 457, 458, 460, 497, 499, 1415, 8064, 8065, 8066, 8067,
  8068, 8069, 8070, 8071, 8080, 8081, 8082, 8083, 8084, 8085, 8086, 8087, 8096,
  8097, 8098, 8099, 8100, 8101, 8102, 8103, 8114, 8115, 8116, 8119, 8130, 8131,
  8132, 8135, 8178, 8179, 8180, 8183, 64256, 64257, 64258, 64258, 64260, 64261,
  64262, 64275, 64276, 64277, 64278, 64279, 55297, 55298, 55299, 55300, 55301,
  55302, 55323, 55354,
];

const Erlang_String = {
  // Start titlecase/1
  "titlecase/1": (subject) => {
    if (Type.isBitstring(subject)) {
      if (Bitstring.isEmpty(subject)) {
        return Bitstring.fromText("");
      }

      if (Bitstring.isText(subject)) {
        let list = subject.text.split("");

        const first_char = list[0];

        if (
          titlecase_unsupported_codepoints.includes(first_char.codePointAt(0))
        ) {
          // Erlang's has a strange uppercase implementation for Combined Diaeresis.
          // Examples: ß, Ǆ
          Interpreter.raiseArgumentError(`${first_char} is not supported`);
        }

        list[0] = first_char.toUpperCase();

        return Bitstring.fromText(list.join(""));
      }

      console.log(subject, "not text, not empty");
    }

    if (Type.isList(subject)) {
      subject = Lists["flatten/1"](subject);

      if (subject.data.length === 0) {
        return Type.list([]);
      }

      let clone = Utils.shallowCloneArray(subject.data);

      const first = clone[0];

      if (Type.isInteger(first)) {
        const firstChar = String.fromCodePoint(Number(first.value))
          .toUpperCase()
          .codePointAt(0);

        clone[0] = Type.integer(firstChar);

        return Type.list(clone);
      }
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":string.titlecase/1", [subject]),
    );
  },
  // End titlecase/1
  // Deps: [:lists.flatten/1]
};

export default Erlang_String;
