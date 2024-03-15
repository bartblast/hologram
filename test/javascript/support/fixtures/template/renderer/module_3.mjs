"use strict";

import {putComponentState} from "../../../helpers.mjs";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule3Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module3",
    "__props__",
    0,
    "public",
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.list([]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module3",
    "init",
    2,
    "public",
    [
      {
        params: (_vars) => [
          Type.matchPlaceholder(),
          Type.variablePattern("component"),
        ],
        guards: [],
        body: (vars) => {
          return putComponentState(
            vars.component,
            Type.map([
              [Type.atom("a"), Type.integer(11)],
              [Type.atom("b"), Type.integer(22)],
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module3",
    "template",
    0,
    "public",
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
                  return Type.list([
                    Type.tuple([
                      Type.atom("element"),
                      Type.bitstring("div"),
                      Type.list([]),
                      Type.list([
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring("state_a = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("a")),
                          ]),
                        ]),
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring(", state_b = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("b")),
                          ]),
                        ]),
                      ]),
                    ]),
                  ]);
                },
              },
            ],
            context,
          );
          Interpreter.updateVarsToMatchedValues(vars);
          return globalThis.__hologramReturn__;
        },
      },
    ],
  );
}
