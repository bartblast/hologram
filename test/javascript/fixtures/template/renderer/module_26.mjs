"use strict";

import {buildClientStruct} from "../../../../../assets/js/test_support.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule26Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module26",
    "__props__",
    0,
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.list([
            Type.tuple([
              Type.atom("prop_3"),
              Type.atom("string"),
              Type.list([]),
            ]),
            Type.tuple([
              Type.atom("prop_1"),
              Type.atom("string"),
              Type.list([]),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module26",
    "init",
    2,
    [
      {
        params: (_vars) => [
          Type.variablePattern("props"),
          Type.variablePattern("client"),
        ],
        guards: [],
        body: (vars) => {
          return buildClientStruct({
            state: vars.props,
          });
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module26",
    "template",
    0,
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (vars) => {
          globalThis.__hologramReturn__ = Type.anonymousFunction(
            1,
            [
              {
                params: (_vars) => [Type.variablePattern("vars")],
                guards: [],
                body: (vars) => {
                  Interpreter.matchOperator(
                    vars.vars,
                    Type.matchPlaceholder(),
                    vars,
                  );
                  Interpreter.updateVarsToMatchedValues(vars);
                  return Type.list([]);
                },
              },
            ],
            vars,
          );
          Interpreter.updateVarsToMatchedValues(vars);
          return globalThis.__hologramReturn__;
        },
      },
    ],
  );
}
