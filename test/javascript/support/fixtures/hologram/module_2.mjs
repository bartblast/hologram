"use strict";

import {putAction, putContext, putState} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Module2 do
  use Hologram.Component

  def action(:my_action_2, %{a: a, b: b, event: event}, component) do
    component
    |> put_state(:x, a + b + 2)
    |> put_context(:event, event)
    |> put_action(name: :my_action_6, params: [c: 10, d: 20], target: "my_component_2")
  end

  def template do
    ~H""
  end
end
*/
export function defineModule2Fixture() {
  Interpreter.defineElixirFunction("Module2", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action_2"),
        Type.map([
          [Type.atom("a"), Type.variablePattern("a")],
          [Type.atom("b"), Type.variablePattern("b")],
          [Type.atom("event"), Type.variablePattern("event")],
        ]),
        Type.variablePattern("component"),
      ],
      guards: [],
      body: (context) => {
        return putAction(
          putContext(
            putState(
              context.vars.component,
              Type.map([
                [
                  Type.atom("x"),
                  Erlang["+/2"](
                    Erlang["+/2"](context.vars.a, context.vars.b),
                    Type.integer(2n),
                  ),
                ],
              ]),
            ),
            Type.map([[Type.atom("event"), context.vars.event]]),
          ),
          Type.actionStruct({
            name: Type.atom("my_action_6"),
            params: Type.map([
              [Type.atom("c"), Type.integer(10)],
              [Type.atom("d"), Type.integer(20)],
            ]),
            target: Type.bitstring("my_component_2"),
          }),
        );
      },
    },
  ]);
}
