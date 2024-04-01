"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

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

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");

describe("getEntry()", () => {
  it("entry exists", () => {
    ComponentRegistry.data = Type.map([
      [cid1, "dummy_1"],
      [cid2, "dummy_2"],
    ]);

    const result = ComponentRegistry.getEntry(cid2);

    assert.equal(result, "dummy_2");
  });

  it("entry doesn't exist", () => {
    const result = ComponentRegistry.getEntry(cid1);
    assert.isNull(result);
  });
});

it("hydrate()", () => {
  ComponentRegistry.data = Type.map([
    [Type.atom("a"), Type.integer(1)],
    [Type.atom("b"), Type.integer(2)],
  ]);

  const data = Type.map([
    [Type.atom("c"), Type.integer(3)],
    [Type.atom("a"), Type.integer(4)],
  ]);

  ComponentRegistry.hydrate(data);

  assert.deepStrictEqual(ComponentRegistry.data, data);
});
