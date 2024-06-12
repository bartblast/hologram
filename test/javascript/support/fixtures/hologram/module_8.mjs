"use strict";

import {putPage} from "../../helpers.mjs";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Module8 do
  use Hologram.Component

  def action(:my_action_8, _params, component) do
    put_page(component, MyPage)
  end

  def template do
    ~H""
  end
end
end

*/
export function defineModule8Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Module8",
    "action",
    3,
    "public",
    [
      {
        params: (_context) => [
          Type.atom("my_action_8"),
          Type.matchPlaceholder(),
          Type.variablePattern("component"),
        ],
        guards: [],
        body: (context) => {
          return putPage(context.vars.component, Type.alias("MyPage"));
        },
      },
    ],
  );
}
