"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule1Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_ExJsConsistency_MatchOperator_Module1",
    "test_a",
    1,
    "public",
    [
      {
        params: (vars) => [
          Interpreter.matchOperator(
            Type.integer(1n),
            Type.variablePattern("a"),
            vars,
          ),
        ],
        guards: [],
        body: (vars) => {
          return Type.map([[Type.atom("a"), vars.a]]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_ExJsConsistency_MatchOperator_Module1",
    "test_b",
    1,
    "public",
    [
      {
        params: (vars) => [
          Interpreter.matchOperator(
            Type.variablePattern("a"),
            Type.integer(1n),
            vars,
          ),
        ],
        guards: [],
        body: (vars) => {
          return Type.map([[Type.atom("a"), vars.a]]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_ExJsConsistency_MatchOperator_Module1",
    "test_c",
    1,
    "public",
    [
      {
        params: (vars) => [
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.integer(1n),
              Type.variablePattern("b"),
              vars,
              false,
            ),
            Type.variablePattern("a"),
            vars,
          ),
        ],
        guards: [],
        body: (vars) => {
          return Type.map([
            [Type.atom("a"), vars.a],
            [Type.atom("b"), vars.b],
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_ExJsConsistency_MatchOperator_Module1",
    "test_d",
    1,
    "public",
    [
      {
        params: (vars) => [
          Interpreter.matchOperator(
            Interpreter.matchOperator(
              Type.variablePattern("b"),
              Type.integer(1n),
              vars,
              false,
            ),
            Type.variablePattern("a"),
            vars,
          ),
        ],
        guards: [],
        body: (vars) => {
          return Type.map([
            [Type.atom("a"), vars.a],
            [Type.atom("b"), vars.b],
          ]);
        },
      },
    ],
  );
}
