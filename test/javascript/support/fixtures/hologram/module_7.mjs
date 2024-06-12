"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Module7 do
  use Hologram.Page

  route "/hologram-test-fixtures-module7"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H""
  end
end

*/
export function defineModule7Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Module7",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](Type.list([]));
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Module7",
    "__route__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.bitstring("/hologram-test-fixtures-module7");
        },
      },
    ],
  );
}
