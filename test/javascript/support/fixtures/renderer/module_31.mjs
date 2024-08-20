"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule31Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module31",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module31",
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
                    Type.tuple([Type.atom("text"), Type.bitstring("31a,")]),
                    Type.tuple([
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module32",
                      ),
                      Type.list(),
                      Type.list([
                        Type.tuple([Type.atom("text"), Type.bitstring("31b,")]),
                        Type.tuple([
                          Type.atom("component"),
                          Type.atom(
                            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module33",
                          ),
                          Type.list(),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("31c,"),
                            ]),
                            Type.tuple([
                              Type.atom("element"),
                              Type.bitstring("slot"),
                              Type.list(),
                              Type.list(),
                            ]),
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring(",31x,"),
                            ]),
                          ]),
                        ]),
                        Type.tuple([Type.atom("text"), Type.bitstring("31y,")]),
                      ]),
                    ]),
                    Type.tuple([Type.atom("text"), Type.bitstring("31z")]),
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
