"use strict";

import Interpreter from "../../../../../../assets/js/interpreter.mjs";
import Type from "../../../../../../assets/js/type.mjs";

// The keyed element the compiler writes for a place in this template.
const keyedElement = (tagName, index, children) =>
  Type.tuple([
    Type.atom("element"),
    Type.bitstring(tagName),
    Type.list([
      Type.tuple([
        Type.bitstring("$key"),
        Type.keywordList([
          [Type.atom("text"), Type.bitstring(`7a8b9c:${index}`)],
        ]),
      ]),
    ]),
    Type.list(children),
  ]);

// A stateless component whose template renders two top-level elements, the first with a child:
// <div><span>a</span></div><p>b</p>
export function defineClientOnlyModule6Fixture() {
  Interpreter.defineElixirFunction(
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module6",
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
    "Hologram.Test.Fixtures.Template.Renderer.ClientOnly.Module6",
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
                  return Type.list([
                    keyedElement("div", 0, [
                      keyedElement("span", 1, [
                        Type.tuple([Type.atom("text"), Type.bitstring("a")]),
                      ]),
                    ]),
                    keyedElement("p", 2, [
                      Type.tuple([Type.atom("text"), Type.bitstring("b")]),
                    ]),
                  ]);
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
