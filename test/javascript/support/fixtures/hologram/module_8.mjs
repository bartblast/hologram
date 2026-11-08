"use strict";

import Interpreter from "../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Module8 do
  use Hologram.Component

  state :count, :integer, default: 0
  state :password, :string, default: "", secret: true
  state :token, :string, default: "none", secret: true

  def template do
    ~HOLO""
  end
end

*/
export function defineModule8Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Module8",
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
              Type.atom("password"),
              Type.atom("string"),
              Type.keywordList([
                [Type.atom("default"), Type.bitstring("")],
                [Type.atom("secret"), Type.boolean(true)],
              ]),
            ]),
            Type.tuple([
              Type.atom("token"),
              Type.atom("string"),
              Type.keywordList([
                [Type.atom("default"), Type.bitstring("none")],
                [Type.atom("secret"), Type.boolean(true)],
              ]),
            ]),
          ]);
        },
      },
    ],
  );
}
