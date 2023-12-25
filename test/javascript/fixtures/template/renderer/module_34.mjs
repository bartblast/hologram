"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineHologramTestFixturesTemplateRendererModule34() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module34",
    "__props__",
    0,
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.list([
            Type.tuple([Type.atom("a"), Type.atom("string"), Type.list([])]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module34",
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
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Interpreter.dotOperator(vars.vars, Type.atom("a")),
                      ]),
                    ]),
                    Type.tuple([Type.atom("text"), Type.bitstring(",")]),
                    Type.tuple([
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module35",
                      ),
                      Type.list([
                        Type.tuple([
                          Type.bitstring("cid"),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("component_35"),
                            ]),
                          ]),
                        ]),
                        Type.tuple([
                          Type.bitstring("a"),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("35a_prop"),
                            ]),
                          ]),
                        ]),
                      ]),
                      Type.list([
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("b")),
                          ]),
                        ]),
                        Type.tuple([Type.atom("text"), Type.bitstring(",")]),
                        Type.tuple([
                          Type.atom("component"),
                          Type.atom(
                            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module36",
                          ),
                          Type.list([
                            Type.tuple([
                              Type.bitstring("cid"),
                              Type.list([
                                Type.tuple([
                                  Type.atom("text"),
                                  Type.bitstring("component_36"),
                                ]),
                              ]),
                            ]),
                            Type.tuple([
                              Type.bitstring("a"),
                              Type.list([
                                Type.tuple([
                                  Type.atom("text"),
                                  Type.bitstring("36a_prop"),
                                ]),
                              ]),
                            ]),
                          ]),
                          Type.list([
                            Type.tuple([
                              Type.atom("expression"),
                              Type.tuple([
                                Interpreter.dotOperator(
                                  vars.vars,
                                  Type.atom("c"),
                                ),
                              ]),
                            ]),
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring(","),
                            ]),
                            Type.tuple([
                              Type.atom("element"),
                              Type.bitstring("slot"),
                              Type.list([]),
                              Type.list([]),
                            ]),
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring(","),
                            ]),
                            Type.tuple([
                              Type.atom("expression"),
                              Type.tuple([
                                Interpreter.dotOperator(
                                  vars.vars,
                                  Type.atom("x"),
                                ),
                              ]),
                            ]),
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring(","),
                            ]),
                          ]),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("y")),
                          ]),
                        ]),
                        Type.tuple([Type.atom("text"), Type.bitstring(",")]),
                      ]),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Interpreter.dotOperator(vars.vars, Type.atom("z")),
                      ]),
                    ]),
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
