"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule12Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module12",
    "__props__",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module12",
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
                      Type.atom("expression"),
                      Type.tuple([
                        Interpreter.dotOperator(
                          context.vars.vars,
                          Type.atom("a"),
                        ),
                      ]),
                    ]),
                    Type.tuple([Type.atom("text"), Type.bitstring(",")]),
                    Type.tuple([
                      Type.atom("element"),
                      Type.bitstring("slot"),
                      Type.list(),
                      Type.list(),
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
