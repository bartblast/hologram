"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule97Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module97",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return (
            Interpreter.setFrameLine(2),
            Elixir_Enum["reverse/1"](Type.list([]))
          );
        },
        line: 2,
        blame: {params: [], guards: []},
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module97",
    "read_b",
    1,
    "public",
    [
      {
        params: (_context) => [Type.variablePattern("map_0")],
        guards: [],
        body: (context) => {
          return (
            Interpreter.setFrameLine(5),
            Interpreter.dotOperator(context.vars.map_0, Type.atom("b"))
          );
        },
        line: 5,
        blame: {params: ["map"], guards: []},
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module97",
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
                  (Interpreter.setFrameLine(9),
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
                        globalThis.Elixir_Hologram_Test_Fixtures_Template_Renderer_Module97[
                          "read_b/1"
                        ](
                          (Interpreter.setFrameLine(1),
                          Erlang_Maps["from_list/1"](Type.list([]))),
                        )),
                      ]),
                    ]),
                  ]);
                },
                line: 9,
              },
            ],
            context,
            "-template/0-fun-0-",
          );
          Interpreter.updateVarsToMatchedValues(context);
          return globalThis.Hologram.return;
        },
        line: 8,
        blame: {params: [], guards: []},
      },
    ],
  );
}
