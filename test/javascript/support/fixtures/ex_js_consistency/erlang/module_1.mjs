"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule1Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module1",
    "fun_0",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.integer(123);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module1",
    "fun_1",
    1,
    "public",
    [
      {
        params: (_context) => [Type.variablePattern("x")],
        guards: [],
        body: (context) => {
          return Erlang["+/2"](context.vars.x, Type.integer(100));
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module1",
    "fun_2",
    2,
    "public",
    [
      {
        params: (_context) => [
          Type.variablePattern("x"),
          Type.variablePattern("y"),
        ],
        guards: [],
        body: (context) => {
          return Erlang["+/2"](context.vars.x, context.vars.y);
        },
      },
    ],
  );
}
