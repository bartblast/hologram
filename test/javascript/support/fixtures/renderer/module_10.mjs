"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule10Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module10",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module10",
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
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module11",
                      ),
                      Type.list([
                        Type.tuple([
                          Type.bitstring("cid"),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("component_11"),
                            ]),
                          ]),
                        ]),
                      ]),
                      Type.list([
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
                          Type.atom("component"),
                          Type.atom(
                            "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module12",
                          ),
                          Type.list([
                            Type.tuple([
                              Type.bitstring("cid"),
                              Type.list([
                                Type.tuple([
                                  Type.atom("text"),
                                  Type.bitstring("component_12"),
                                ]),
                              ]),
                            ]),
                          ]),
                          Type.list([
                            Type.tuple([
                              Type.atom("expression"),
                              Type.tuple([
                                Interpreter.dotOperator(
                                  context.vars.vars,
                                  Type.atom("a"),
                                ),
                              ]),
                            ]),
                          ]),
                        ]),
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
