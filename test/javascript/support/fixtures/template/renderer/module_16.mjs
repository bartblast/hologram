"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule16Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module16",
    "__props__",
    0,
    "public",
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
              Type.atom("prop_2"),
              Type.atom("integer"),
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module16",
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
                      Type.atom("text"),
                      Type.bitstring("component vars = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Elixir_Kernel["inspect/1"](
                          Erlang_Lists["sort/1"](
                            Erlang_Maps["to_list/1"](vars.vars),
                          ),
                        ),
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
