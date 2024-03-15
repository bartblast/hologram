"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule25Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module25",
    "__layout_module__",
    0,
    "public",
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.atom(
            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module26",
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module25",
    "__layout_props__",
    0,
    "public",
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.list([
            Type.tuple([Type.atom("prop_1"), Type.bitstring("prop_value_1")]),
            Type.tuple([Type.atom("prop_2"), Type.bitstring("prop_value_2")]),
            Type.tuple([Type.atom("prop_3"), Type.bitstring("prop_value_3")]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module25",
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module25",
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
                  return Type.list([]);
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
