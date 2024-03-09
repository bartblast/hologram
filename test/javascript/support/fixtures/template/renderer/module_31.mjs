"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule31Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module31",
    "__props__",
    0,
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module31",
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
                  return Type.list([
                    Type.tuple([Type.atom("text"), Type.bitstring("31a,")]),
                    Type.tuple([
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module32",
                      ),
                      Type.list([]),
                      Type.list([
                        Type.tuple([Type.atom("text"), Type.bitstring("31b,")]),
                        Type.tuple([
                          Type.atom("component"),
                          Type.atom(
                            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module33",
                          ),
                          Type.list([]),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("31c,"),
                            ]),
                            Type.tuple([
                              Type.atom("element"),
                              Type.bitstring("slot"),
                              Type.list([]),
                              Type.list([]),
                            ]),
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring(",31x,"),
                            ]),
                          ]),
                        ]),
                        Type.tuple([Type.atom("text"), Type.bitstring("31y,")]),
                      ]),
                    ]),
                    Type.tuple([Type.atom("text"), Type.bitstring("31z")]),
                  ]);
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
