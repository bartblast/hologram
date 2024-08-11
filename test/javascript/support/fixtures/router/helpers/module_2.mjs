"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule2Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Router.Helpers.Module2",
    "__params__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](
            Type.list([
              Type.tuple([Type.atom("param_2"), Type.nil(), Type.list()]),
              Type.tuple([Type.atom("param_1"), Type.nil(), Type.list()]),
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Router.Helpers.Module2",
    "__route__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.bitstring(
            "/hologram-test-fixtures-router-helpers-module2/:param_1/:param_2",
          );
        },
      },
    ],
  );
}
