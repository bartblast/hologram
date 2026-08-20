"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule89Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module89",
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
              Type.atom("string"),
              Type.list([
                Type.tuple([Type.atom("required"), Type.atom("true")]),
              ]),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module89",
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
                      Type.bitstring("prop_aaa = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        Erlang_Maps["get/2"](
                          Type.atom("aaa"),
                          context.vars.vars,
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
