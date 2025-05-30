// Fixture used only in client tests.

"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
defmodule Hologram.Test.Fixtures.Template.Renderer.Module55 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    <div>
      <button $click="my_action">Click me</button>
    </div>
    """
  end
end
*/
export function defineModule55Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module55",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module55",
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
                        Type.tuple([Type.atom("text"), Type.bitstring("\n  ")]),
                        Type.tuple([
                          Type.atom("element"),
                          Type.bitstring("button"),
                          Type.list([
                            Type.tuple([
                              Type.bitstring("$click"),
                              Type.list([
                                Type.tuple([
                                  Type.atom("text"),
                                  Type.bitstring("my_action"),
                                ]),
                              ]),
                            ]),
                          ]),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("Click me"),
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
