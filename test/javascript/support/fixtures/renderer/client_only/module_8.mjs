"use strict";

import {putState} from "../../../helpers.mjs";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

export function defineClientOnlyModule8Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module8",
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
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module8",
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
              Type.keywordList([[Type.atom("default"), Type.integer(1)]]),
            ]),
            Type.tuple([
              Type.atom("b"),
              Type.atom("string"),
              Type.keywordList([[Type.atom("default"), Type.bitstring("abc")]]),
            ]),
            Type.tuple([Type.atom("c"), Type.atom("map"), Type.keywordList()]),
          ]);
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module8",
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
          const component = context.vars.component;

          return putState(
            component,
            Type.map([
              [Type.atom("b"), Type.bitstring("xyz")],
              [
                Type.atom("c"),
                Erlang_Maps["get/2"](Type.atom("state"), component),
              ],
            ]),
          );
        },
      },
    ],
  );

  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module8",
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
