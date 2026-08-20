"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule91Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module91",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([
            Type.tuple([
              Type.atom("aaa"),
              Type.atom("atom"),
              Type.list([
                Type.tuple([
                  Type.atom("values"),
                  Type.list([Type.atom("small"), Type.atom("large")]),
                ]),
              ]),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module91",
    "template",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (context) => {
          globalThis.Hologram.return = Type.anonymousFunction(
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
          return globalThis.Hologram.return;
        },
      },
    ],
  );
}
