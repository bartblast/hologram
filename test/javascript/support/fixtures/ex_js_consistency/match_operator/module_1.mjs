"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule1Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
    "test_a",
    1,
    "public",
    [
      {
        params: (context) => [
          Interpreter.matchOperator(
            Type.integer(1n),
            Type.variablePattern("a"),
            context,
          ),
        ],
        guards: [],
        body: (context) => {
          return Type.map([[Type.atom("a"), context.vars.a]]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
    "test_b",
    1,
    "public",
    [
      {
        params: (context) => [
          Interpreter.matchOperator(
            Type.variablePattern("a"),
            Type.integer(1n),
            context,
          ),
        ],
        guards: [],
        body: (context) => {
          return Type.map([[Type.atom("a"), context.vars.a]]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
    "test_c",
    1,
    "public",
    [
      {
        params: (context) => [
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.integer(1n),
              Type.variablePattern("b"),
              context,
            ),
            Type.variablePattern("a"),
            context,
          ),
        ],
        guards: [],
        body: (context) => {
          return Type.map([
            [Type.atom("a"), context.vars.a],
            [Type.atom("b"), context.vars.b],
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1",
    "test_d",
    1,
    "public",
    [
      {
        params: (context) => [
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("b"),
              Type.integer(1n),
              context,
            ),
            Type.variablePattern("a"),
            context,
          ),
        ],
        guards: [],
        body: (context) => {
          return Type.map([
            [Type.atom("a"), context.vars.a],
            [Type.atom("b"), context.vars.b],
          ]);
        },
      },
    ],
  );
}
