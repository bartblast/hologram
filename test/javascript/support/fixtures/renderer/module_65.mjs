"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule65Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module65",
    "__props__",
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
                Type.atom("prop_3"),
                Type.atom("integer"),
                Type.list([
                  Type.tuple([Type.atom("default"), Type.integer(123n)]),
                ]),
              ]),
              Type.tuple([
                Type.atom("prop_2"),
                Type.atom("atom"),
                Type.list([]),
              ]),
              Type.tuple([
                Type.atom("prop_1"),
                Type.atom("string"),
                Type.list([
                  Type.tuple([Type.atom("default"), Type.bitstring("abc")]),
                ]),
              ]),
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module65",
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
                      Type.bitstring("component vars = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Elixir_Kernel["inspect/2"](
                          context.vars.vars,
                          Type.list([
                            Type.tuple([
                              Type.atom("custom_options"),
                              Type.list([
                                Type.tuple([
                                  Type.atom("sort_maps"),
                                  Type.atom("true"),
                                ]),
                              ]),
                            ]),
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
