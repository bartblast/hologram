"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineModule24Fixture() {
  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module24",
    "__layout_module__",
    0,
    "public",
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.atom(
            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module23",
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module24",
    "__layout_props__",
    0,
    "public",
    [
      {
        params: (_vars) => [],
        guards: [],
        body: (_vars) => {
          return Type.list([
            Type.tuple([Type.atom("key_1"), Type.bitstring("prop_value_1")]),
            Type.tuple([Type.atom("key_2"), Type.bitstring("prop_value_2")]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module24",
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
    "Elixir_Hologram_Test_Fixtures_Template_Renderer_Module24",
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
