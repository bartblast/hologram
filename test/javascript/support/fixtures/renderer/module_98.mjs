"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule98Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module98",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return (
            Interpreter.setFrameLine(1),
            Elixir_Enum["reverse/1"](Type.list([]))
          );
        },
        line: 1,
        blame: {params: [], guards: []},
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module98",
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
                params: (_context) => [Type.variablePattern("vars_0")],
                guards: [],
                body: (context) => {
                  (Interpreter.setFrameLine(6),
                    Interpreter.matchOperator(
                      context.vars.vars_0,
                      Type.matchPlaceholder(),
                      context,
                    ));
                  Interpreter.updateVarsToMatchedValues(context);
                  return Type.list([
                    Type.tuple([Type.atom("text"), Type.bitstring("b = ")]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        (Interpreter.setFrameLine(1),
                        Interpreter.dotOperator(
                          (Interpreter.setFrameLine(1),
                          Erlang_Maps["from_list/1"](Type.list([]))),
                          Type.atom("b"),
                        )),
                      ]),
                    ]),
                  ]);
                },
                line: 6,
              },
            ],
            context,
            "-template/0-fun-0-",
          );
          Interpreter.updateVarsToMatchedValues(context);
          return globalThis.Hologram.return;
        },
        line: 5,
        blame: {params: [], guards: []},
      },
    ],
  );
}
