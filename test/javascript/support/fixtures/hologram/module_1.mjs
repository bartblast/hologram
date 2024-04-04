"use strict";

import {putContext, putState} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

export function defineModule1Fixture() {
  // Based on:
  // def action(:my_action, %{a: a, b: b, event: event}, component) do
  //   component
  //   |> put_state(:c, a + b)
  //   |> put_context(:event, event)
  // end
  Interpreter.defineElixirFunction("Module1", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action"),
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
              [Type.atom("c"), Erlang["+/2"](context.vars.a, context.vars.b)],
            ]),
          ),
          Type.map([[Type.atom("event"), context.vars.event]]),
        );
      },
    },
  ]);
}
