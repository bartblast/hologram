"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule21Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module21",
    "__layout_module__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.atom("Elixir.Hologram.Test.Fixtures.LayoutFixture");
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module21",
    "__layout_props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list();
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module21",
    "__params__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](
            Type.list([
              Type.tuple([
                Type.atom("key_2"),
                Type.atom("string"),
                Type.list(),
              ]),
              Type.tuple([
                Type.atom("key_1"),
                Type.atom("string"),
                Type.list(),
              ]),
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module21",
    "template",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (context) => {
          globalThis.hologram.return = Type.anonymousFunction(
            1,
            [
              {
                params: (_context) => [Type.variablePattern("vars")],
                guards: [],
                body: (context) => {
                  Interpreter.matchOperator(
                    context.vars.vars,
                    Type.matchPlaceholder(),
                    context,
                  );
                  Interpreter.updateVarsToMatchedValues(context);
                  return Type.list([
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring("page vars = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Elixir_Kernel["inspect/2"](
                          context.vars.vars,
                          Type.keywordList([
                            [
                              Type.atom("custom_options"),
                              Type.keywordList([
                                [Type.atom("sort_maps"), Type.boolean(true)],
                              ]),
                            ],
                          ]),
                        ),
                      ]),
                    ]),
                  ]);
                },
              },
            ],
            context,
          );
          Interpreter.updateVarsToMatchedValues(context);
          return globalThis.hologram.return;
        },
      },
    ],
  );
}
