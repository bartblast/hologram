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

defmodule Module3 do
  use Hologram.Component

  def action(:my_action_3a, %{a: a, b: b, event: event}, component) do
    component
    |> put_state(:x, a + b + 3)
    |> put_context(:event, event)
    |> put_action(name: :my_action_3b, params: [c: 10, d: 20], target: "my_component_2")
  end
  
  def action(:my_action_3b, %{c: c, d: d}, component) do
    component
    |> put_state(:y, c + d + 3)
    |> put_context(:my_context, 3)
  end

  def template do
    ~H""
  end
end
*/
export function defineModule3Fixture() {
  Interpreter.defineElixirFunction("Module3", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action_3a"),
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
                    Type.integer(3n),
                  ),
                ],
              ]),
            ),
            Type.map([[Type.atom("event"), context.vars.event]]),
          ),
          actionFixture({
            name: Type.atom("my_action_3b"),
            params: Type.map([
              [Type.atom("c"), Type.integer(10)],
              [Type.atom("d"), Type.integer(20)],
            ]),
            target: Type.nil(),
          }),
        );
      },
    },
    {
      params: (_context) => [
        Type.atom("my_action_3b"),
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
                  Type.integer(3n),
                ),
              ],
            ]),
          ),
          Type.map([[Type.atom("my_context"), Type.integer(3n)]]),
        );
      },
    },
  ]);
}
