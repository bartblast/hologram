"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

// A stateless component whose template renders one element carrying the key of its place, as the
// compiler writes it.
export function defineClientOnlyModule5Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module5",
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
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module5",
    "template",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.anonymousFunction(
            1,
            [
              {
                params: (_context) => [Type.variablePattern("vars")],
                guards: [],
                body: (_context) => {
                  return Type.list([
                    Type.tuple([
                      Type.atom("element"),
                      Type.bitstring("div"),
                      Type.list([
                        Type.tuple([
                          Type.bitstring("$key"),
                          Type.keywordList([
                            [Type.atom("text"), Type.bitstring("4d5e6f:0")],
                          ]),
                        ]),
                      ]),
                      Type.list(),
                    ]),
                  ]);
                },
              },
            ],
            {vars: {}},
          );
        },
      },
    ],
  );
}
