"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module10 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-clientonly-module10/:id"

  param :id, :integer

  state :a, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  def template do
    ~HOLO""
  end
end

*/
export function defineClientOnlyModule10Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module10",
    "__params__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([
            Type.tuple([
              Type.atom("id"),
              Type.atom("integer"),
              Type.keywordList(),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module10",
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
              Type.atom("a"),
              Type.atom("integer"),
              Type.keywordList(),
            ]),
          ]);
        },
      },
    ],
  );
}
