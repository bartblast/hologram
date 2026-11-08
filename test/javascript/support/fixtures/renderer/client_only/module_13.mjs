"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module13 do
  use Hologram.Component

  state :password, :string, default: "hunter2", secret: true

  def init(_props, component) do
    component.state.pasword
    component
  end

  def template do
    ~HOLO""
  end
end

*/
export function defineClientOnlyModule13Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module13",
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
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module13",
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
              Type.atom("password"),
              Type.atom("string"),
              Type.keywordList([
                [Type.atom("default"), Type.bitstring("hunter2")],
                [Type.atom("secret"), Type.boolean(true)],
              ]),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module13",
    "init",
    2,
    "public",
    [
      {
        params: (_context) => [
          Type.matchPlaceholder(),
          Type.variablePattern("component"),
        ],
        guards: [],
        body: (context) => {
          Interpreter.dotOperator(
            Interpreter.dotOperator(context.vars.component, Type.atom("state")),
            Type.atom("pasword"),
          );

          return context.vars.component;
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module13",
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
