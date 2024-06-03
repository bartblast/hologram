"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Module9 do
  use Hologram.Component

  def action(:my_action_9, _params, component) do
    component
  end

  def template do
    ~H""
  end
end
end

*/
export function defineModule9Fixture() {
  Interpreter.defineElixirFunction("Hologram.Module9", "action", 3, "public", [
    {
      params: (_context) => [
        Type.atom("my_action_9"),
        Type.matchPlaceholder(),
        Type.variablePattern("component"),
      ],
      guards: [],
      body: (context) => {
        return context.vars.component;
      },
    },
  ]);
}
