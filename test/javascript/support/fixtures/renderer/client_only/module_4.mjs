"use strict";

import {putAction, putState} from "../../../helpers.mjs";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

// init/2 queues an action with a delay, which the renderer must hand to the timer rather than to
// the queue.
export function defineClientOnlyModule4Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module4",
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
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module4",
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
          const action = Type.map([
            [Type.atom("delay"), Type.integer(1000)],
            [Type.atom("name"), Type.atom("delayed_action_from_init")],
            [Type.atom("params"), Type.map()],
          ]);

          return putAction(
            putState(
              context.vars.component,
              Type.map([[Type.atom("initialized"), Type.boolean(true)]]),
            ),
            action,
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module4",
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
