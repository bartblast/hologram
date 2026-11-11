"use strict";

import {putState} from "../../../helpers.mjs";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

/*
Based on:

defmodule Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module9 do
  use Hologram.Component

  prop :label, :string

  state :a, :integer

  def init(_props, component) do
    put_state(component, a: 1, c: 3, b: 2)
  end

  def template do
    ~HOLO""
  end
end

*/
export function defineClientOnlyModule9Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module9",
    "__props__",
    0,
    "public",
    [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => {
          return Type.list([
            Type.tuple([
              Type.atom("label"),
              Type.atom("string"),
              Type.keywordList(),
            ]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module9",
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

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module9",
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
          return putState(
            context.vars.component,
            Type.map([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("c"), Type.integer(3)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module9",
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
