"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.ComponentRegistry.Module2 do
  use Hologram.Component

  state :count, :integer, default: 0
  state :label, :string, default: "", secret: false

  def template do
    ~HOLO""
  end
end

*/
export function defineModule2Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.ComponentRegistry.Module2",
    "__state__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([
            Type.tuple([
              Type.atom("count"),
              Type.atom("integer"),
              Type.keywordList([[Type.atom("default"), Type.integer(0)]]),
            ]),
            Type.tuple([
              Type.atom("label"),
              Type.atom("string"),
              Type.keywordList([
                [Type.atom("default"), Type.bitstring("")],
                [Type.atom("secret"), Type.boolean(false)],
              ]),
            ]),
          ]);
        },
      },
    ],
  );
}
