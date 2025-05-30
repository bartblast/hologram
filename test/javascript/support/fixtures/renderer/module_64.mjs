"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule64Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module64",
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
              Type.tuple([Type.atom("my_prop"), Type.atom("any"), Type.list()]),
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module64",
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
                      Type.bitstring("my_prop = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Elixir_Kernel["inspect/1"](
                          Interpreter.dotOperator(
                            context.vars.vars,
                            Type.atom("my_prop"),
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
          Interpreter.updateVarsToMatchedValues(context);
          return globalThis.hologram.return;
        },
      },
    ],
  );
}
