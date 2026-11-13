"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule122Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module122",
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
        line: 6,
        blame: {params: [], guards: []},
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module122",
    "__layout_props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([]);
        },
        line: 6,
        blame: {params: [], guards: []},
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module122",
    "__params__",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module122",
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
                  (Interpreter.setFrameLine(15),
                    Interpreter.matchOperator(
                      context.vars.vars_0,
                      Type.matchPlaceholder(),
                      context,
                    ));
                  Interpreter.updateVarsToMatchedValues(context);
                  return Type.list([
                    Type.tuple([Type.atom("text"), Type.bitstring("var_b = ")]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        (Interpreter.setFrameLine(1),
                        Interpreter.dotOperator(
                          context.vars.vars_0,
                          Type.atom("b"),
                        )),
                      ]),
                    ]),
                    Type.tuple([
                      Type.atom("text"),
                      Type.bitstring(", var_c = "),
                    ]),
                    Type.tuple([
                      Type.atom("expression"),
                      Type.tuple([
                        (Interpreter.setFrameLine(1),
                        Interpreter.dotOperator(
                          context.vars.vars_0,
                          Type.atom("c"),
                        )),
                      ]),
                    ]),
                  ]);
                },
                line: 15,
              },
            ],
            context,
            "-template/0-fun-0-",
          );
          Interpreter.updateVarsToMatchedValues(context);
          return globalThis.Hologram.return;
        },
        line: 14,
        blame: {params: [], guards: []},
      },
    ],
  );
}
