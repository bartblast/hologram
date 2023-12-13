"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

export function defineRendererFixtureModules() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module1",
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module1",
    "init",
    2,
    [
      {
        params: (vars) => [
          Type.matchPlaceholder(),
          Type.variablePattern("client"),
        ],
        guards: [],
        body: (vars) => {
          return vars.client;
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module1",
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
                params: (vars) => [Type.variablePattern("vars")],
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
                        Type.tuple([Type.atom("text"), Type.bitstring("abc")]),
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

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module2",
    "__props__",
    0,
    [
      {
        params: (vars) => [],
        guards: [],
        body: (vars) => {
          return Type.list([
            Type.tuple([Type.atom("c"), Type.atom("string"), Type.list([])]),
            Type.tuple([Type.atom("b"), Type.atom("integer"), Type.list([])]),
            Type.tuple([Type.atom("a"), Type.atom("string"), Type.list([])]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module2",
    "init",
    2,
    [
      {
        params: (vars) => [
          Type.matchPlaceholder(),
          Type.variablePattern("client"),
        ],
        guards: [],
        body: (vars) => {
          return vars.client;
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module2",
    "template",
    0,
    [
      {
        params: (vars) => [],
        guards: [],
        body: (vars) => {
          globalThis.__hologramReturn__ = Type.anonymousFunction(
            1,
            [
              {
                params: (vars) => [Type.variablePattern("vars")],
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
                          Type.bitstring("prop_a = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("a")),
                          ]),
                        ]),
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring(", prop_b = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("b")),
                          ]),
                        ]),
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring(", prop_c = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(vars.vars, Type.atom("c")),
                          ]),
                        ]),
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

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module17",
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module17",
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
                    Type.tuple([Type.atom("text"), Type.bitstring("var_a = ")]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Interpreter.dotOperator(vars.vars, Type.atom("a")),
                      ]),
                    ]),
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring(", var_b = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Interpreter.dotOperator(vars.vars, Type.atom("b")),
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
