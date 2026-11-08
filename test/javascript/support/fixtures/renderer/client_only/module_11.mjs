"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module11 do
  use Hologram.Component

  state :count, :integer, default: 0
  state :password, :string, default: "", secret: true

  def init(_props, _component) do
    %Component{state: %{count: 1, password: "hunter2"}}
  end

  def template do
    ~HOLO""
  end
end

*/
export function defineClientOnlyModule11Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module11",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list();
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module11",
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
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module11",
    "init",
    2,
    "public",
    [
      {
        params: (_context) => [
          Type.matchPlaceholder(),
          Type.matchPlaceholder(),
        ],
        guards: [],
        body: (_context) => {
          return Type.componentStruct({
            state: Type.map([
              [Type.atom("count"), Type.integer(1)],
              [Type.atom("password"), Type.bitstring("hunter2")],
            ]),
          });
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module11",
    "template",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.anonymousFunction(
            1,
            [
              {
                params: (_context) => [Type.variablePattern("vars")],
                guards: [],
                body: (_context) => {
                  return Type.list();
                },
              },
            ],
            {vars: {}},
          );
        },
      },
    ],
  );
}
