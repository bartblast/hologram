"use strict";

import {putContext, putState} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Module1 do
  use Hologram.Component

  def action(:my_action_1, %{a: a, b: b, event: event}, component) do
    component
    |> put_state(:x, a + b + 1)
    |> put_context(:event, event)
  end

  def template do
    ~H""
  end
end
*/
export function defineModule1Fixture() {
  Interpreter.defineElixirFunction("Hologram.Module1", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action_1"),
        Type.map([
          [Type.atom("a"), Type.variablePattern("a")],
          [Type.atom("b"), Type.variablePattern("b")],
          [Type.atom("event"), Type.variablePattern("event")],
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
                Type.atom("x"),
                Erlang["+/2"](
                  Erlang["+/2"](context.vars.a, context.vars.b),
                  Type.integer(1n),
                ),
              ],
            ]),
          ),
          Type.map([[Type.atom("event"), context.vars.event]]),
        );
      },
    },
  ]);
}
