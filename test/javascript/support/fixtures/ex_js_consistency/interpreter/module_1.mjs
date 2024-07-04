"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule1Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1",
    "my_public_fun",
    1,
    "public",
    [
      {
        params: (_context) => [Type.variablePattern("x")],
        guards: [],
        body: (context) => {
          return context.vars.x;
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1",
    "my_public_fun",
    2,
    "public",
    [
      {
        params: (_context) => [Type.variablePattern("x"), Type.integer(2n)],
        guards: [],
        body: (context) => {
          return Erlang["+/2"](context.vars.x, Type.integer(2n));
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.Interpreter.Module1",
    "my_private_fun",
    2,
    "private",
    [
      {
        params: (_context) => [
          Type.variablePattern("x"),
          Type.variablePattern("y"),
        ],
        guards: [],
        body: (context) => {
          return Erlang["-/2"](context.vars.x, context.vars.y);
        },
      },
    ],
  );
}
