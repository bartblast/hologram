"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule67Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module67",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](Type.list([]));
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module67",
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
                params: (_context) => [Type.variablePattern("vars_0")],
                guards: [],
                body: (context) => {
                  Interpreter.matchOperator(
                    context.vars.vars_0,
                    Type.matchPlaceholder(),
                    context,
                  );
                  Interpreter.updateVarsToMatchedValues(context);
                  return Type.list([
                    Type.tuple([
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module68",
                      ),
                      Type.list([]),
                      Type.list([
                        Type.tuple([Type.atom("text"), Type.bitstring("\n  ")]),
                        Interpreter.case(
                          Type.atom("false"),
                          [
                            {
                              match: Type.atom("false"),
                              guards: [],
                              body: (_context) => {
                                return Type.atom("nil");
                              },
                            },
                            {
                              match: Type.atom("true"),
                              guards: [],
                              body: (_context) => {
                                return Type.list([
                                  Type.tuple([
                                    Type.atom("text"),
                                    Type.bitstring("\n    abc\n  "),
                                  ]),
                                ]);
                              },
                            },
                          ],
                          context,
                        ),
                        Type.tuple([Type.atom("text"), Type.bitstring("\n")]),
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
