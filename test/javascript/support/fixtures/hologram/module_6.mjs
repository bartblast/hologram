"use strict";

import {
  actionFixture,
  putAction,
  putContext,
  putState,
} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Module6 do
  use Hologram.Component

  def action(:my_action_6, %{c: c, d: d}, component) do
    component
    |> put_state(:y, c + d + 6)
    |> put_context(:my_context, 6)
  end

  def template do
    ~H""
  end
end
*/
export function defineModule6Fixture() {
  Interpreter.defineElixirFunction("Module6", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action_6"),
        Type.map([
          [Type.atom("c"), Type.variablePattern("c")],
          [Type.atom("d"), Type.variablePattern("d")],
        ]),
        Type.variablePattern("component"),
      ],
      guards: [],
      body: (context) => {
        return putContext(
          putState(
            context.vars.component,
            Type.map([
              [
                Type.atom("y"),
                Erlang["+/2"](
                  Erlang["+/2"](context.vars.c, context.vars.d),
                  Type.integer(6n),
                ),
              ],
            ]),
          ),
          Type.map([[Type.atom("my_context"), Type.integer(6n)]]),
        );
      },
    },
  ]);
}
