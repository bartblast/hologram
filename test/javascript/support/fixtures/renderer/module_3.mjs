"use strict";

import {putState} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule3Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module3",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module3",
    "init",
    2,
    "public",
    [
      {
        params: (_context) => [
          Type.matchPlaceholder(),
          Type.variablePattern("component"),
        ],
        guards: [],
        body: (context) => {
          return putState(
            context.vars.component,
            Type.map([
              [Type.atom("a"), Type.integer(11)],
              [Type.atom("b"), Type.integer(22)],
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module3",
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
                      Type.atom("element"),
                      Type.bitstring("div"),
                      Type.list(),
                      Type.list([
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring("state_a = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(
                              context.vars.vars,
                              Type.atom("a"),
                            ),
                          ]),
                        ]),
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring(", state_b = "),
                        ]),
                        Type.tuple([
                          Type.atom("expression"),
                          Type.tuple([
                            Interpreter.dotOperator(
                              context.vars.vars,
                              Type.atom("b"),
                            ),
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
