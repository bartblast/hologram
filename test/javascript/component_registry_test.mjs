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

describe("ComponentRegistry", () => {
  const cid1 = Type.bitstring("my_component_1");
  const cid2 = Type.bitstring("my_component_2");
  const cid3 = Type.bitstring("my_component_3");

  const module1 = Type.alias("MyModule1");
  const module2 = Type.alias("MyModule2");

  const struct1 = componentStructFixture({
    emittedContext: Type.map([
      [Type.atom("context_1a"), Type.integer(11)],
      [(Type.atom("context_1b"), Type.integer(12))],
    ]),
    state: Type.map([
      [Type.atom("state_1a"), Type.integer(101)],
      [(Type.atom("state_1b"), Type.integer(102))],
    ]),
  });

  const struct2 = componentStructFixture({
    emittedContext: Type.map([
      [Type.atom("context_2a"), Type.integer(21)],
      [(Type.atom("context_2b"), Type.integer(22))],
    ]),
    state: Type.map([
      [Type.atom("state_2a"), Type.integer(201)],
      [(Type.atom("state_2b"), Type.integer(202))],
    ]),
  });

  const entry1 = Type.map([
    [Type.atom("module"), module1],
    [Type.atom("struct"), struct1],
  ]);

  const entry2 = Type.map([
    [Type.atom("module"), module2],
    [Type.atom("struct"), struct2],
  ]);

  beforeEach(() => {
    ComponentRegistry.data = Type.map([
      [cid1, entry1],
      [cid2, entry2],
    ]);
  });

  afterEach(() => {
    ComponentRegistry.data = Type.map([]);
  });

  describe("getEntry()", () => {
    it("entry exists", () => {
      const result = ComponentRegistry.getEntry(cid2);
      assert.equal(result, entry2);
    });

    it("entry doesn't exist", () => {
      const result = ComponentRegistry.getEntry(cid3);
      assert.isNull(result);
    });
  });

  it("hydrate()", () => {
    ComponentRegistry.hydrate("dummyData");
    assert.equal(ComponentRegistry.data, "dummyData");
  });
});
