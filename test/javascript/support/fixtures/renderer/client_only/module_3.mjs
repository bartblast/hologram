"use strict";

import {putState} from "../../../helpers.mjs";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

// init/2 reads component.props rather than the props argument it is also given, so a test can tell
// whether the struct the renderer hands to init already carries them.
export function defineClientOnlyModule3Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module3",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([
            Type.tuple([Type.atom("label"), Type.atom("string"), Type.list()]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module3",
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
              [
                Type.atom("props_seen_by_init"),
                Interpreter.dotOperator(
                  context.vars.component,
                  Type.atom("props"),
                ),
              ],
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module3",
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
                      Type.list(),
                      Type.list([
                        Type.tuple([
                          Type.atom("text"),
                          Type.bitstring("test component"),
                        ]),
                      ]),
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
