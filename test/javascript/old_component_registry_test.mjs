"use strict";

import {
  assert,
  componentStructFixture,
  linkModules,
  unlinkModules,
} from "./support/helpers.mjs";

import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

beforeEach(() => {
  ComponentRegistry.data = Type.map([]);
});

afterEach(() => {
  ComponentRegistry.data = Type.map([]);
});

describe("putComponentState()", () => {
  const cid = Type.bitstring("my_component");

  it("when component struct exists", () => {
    ComponentRegistry.data = Type.map([
      [
        cid,
        Type.map([
          [Type.atom("emitted_context"), "dummy_context"],
          [Type.atom("state"), "dummy_state_1"],
        ]),
      ],
    ]);

    ComponentRegistry.putComponentState(cid, "dummy_state_2");

    assert.deepStrictEqual(
      ComponentRegistry.data,
      Type.map([
        [
          cid,
          Type.map([
            [Type.atom("emitted_context"), "dummy_context"],
            [Type.atom("state"), "dummy_state_2"],
          ]),
        ],
      ]),
    );
  });

  it("when component struct doesn't exist", () => {
    ComponentRegistry.putComponentState(cid, "dummy_state");

    assert.deepStrictEqual(
      ComponentRegistry.data,
      Type.map([[cid, componentStructFixture({state: "dummy_state"})]]),
    );
  });
});

it("putComponentStruct()", () => {
  ComponentRegistry.data = Type.map([
    [
      Type.bitstring("my_component_1"),
      Type.map([
        [Type.atom("emitted_context"), "dummy_context_1"],
        [Type.atom("state"), "dummy_state_1"],
      ]),
    ],
  ]);

  const cid = Type.bitstring("my_component_2");

  const componentData = Type.map([
    [Type.atom("emitted_context"), "dummy_context_2"],
    [Type.atom("state"), "dummy_state_2"],
  ]);

  ComponentRegistry.putComponentStruct(cid, componentData);

  assert.deepStrictEqual(
    ComponentRegistry.data,
    Type.map([
      [
        Type.bitstring("my_component_1"),
        Type.map([
          [Type.atom("emitted_context"), "dummy_context_1"],
          [Type.atom("state"), "dummy_state_1"],
        ]),
      ],
      [
        Type.bitstring("my_component_2"),
        Type.map([
          [Type.atom("emitted_context"), "dummy_context_2"],
          [Type.atom("state"), "dummy_state_2"],
        ]),
      ],
    ]),
  );
});
