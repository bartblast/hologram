// Fixture used only in client tests.

"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
defmodule Hologram.Test.Fixtures.Template.Renderer.Module59 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.Renderer.Module60

  @impl Component
  def template do
    ~HOLO"""
    <Module60 cid="component_60" />
    """
  end
end
*/
export function defineModule59Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.Module59",
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
    "Hologram.Test.Fixtures.Template.Renderer.Module59",
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
                      Type.atom("component"),
                      Type.atom(
                        "Elixir.Hologram.Test.Fixtures.Template.Renderer.Module60",
                      ),
                      Type.list([
                        Type.tuple([
                          Type.bitstring("cid"),
                          Type.list([
                            Type.tuple([
                              Type.atom("text"),
                              Type.bitstring("component_60"),
                            ]),
                          ]),
                        ]),
                      ]),
                      Type.list(),
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
