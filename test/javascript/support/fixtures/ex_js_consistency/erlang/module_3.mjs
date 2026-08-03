"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule3Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module3",
    "format_error",
    2,
    "public",
    [
      {
        params: (_context) => [
          Type.variablePattern("_reason"),
          Type.variablePattern("_stacktrace"),
        ],
        guards: [],
        body: (_context) => {
          return Type.map([[Type.integer(2), Type.bitstring("not a map")]]);
        },
      },
    ],
  );
}
