"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Module7 do
  use Hologram.Page

  route "/hologram-test-fixtures-module7"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end

*/
export function defineModule7Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Module7",
    "__params__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Elixir_Enum["reverse/1"](Type.list());
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Module7",
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
