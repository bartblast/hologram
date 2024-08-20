"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule62Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module62",
    "__layout_module__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.atom("Elixir.Hologram.Test.Fixtures.LayoutFixture");
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module62",
    "__layout_props__",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module62",
    "__params__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](Type.list());
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module62",
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
                    Type.tuple([Type.atom("doctype"), Type.bitstring("html")]),
                    Type.tuple([Type.atom("text"), Type.bitstring("\n")]),
                    Type.tuple([
                      Type.atom("element"),
                      Type.bitstring("html"),
                      Type.list(),
                      Type.list([
                        Type.tuple([Type.atom("text"), Type.bitstring("\n  ")]),
                        Type.tuple([
                          Type.atom("element"),
                          Type.bitstring("body"),
                          Type.list(),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("\n    Module62\n  "),
                            ]),
                          ]),
                        ]),
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
