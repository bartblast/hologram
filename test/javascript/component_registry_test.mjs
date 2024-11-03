"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  initComponentRegistryEntry,
} from "./support/helpers.mjs";

import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");
const cid3 = Type.bitstring("my_component_3");
const cid4 = Type.bitstring("my_component_4");

const module1 = Type.alias("MyModule1");
const module2 = Type.alias("MyModule2");
const module3 = Type.alias("MyModule3");

const emittedContext1 = Type.map([
  [Type.atom("context_1a"), Type.integer(11)],
  [Type.atom("context_1b"), Type.integer(12)],
]);

const emittedContext2 = Type.map([
  [Type.atom("context_2a"), Type.integer(21)],
  [Type.atom("context_2b"), Type.integer(22)],
]);

const emittedContext3 = Type.map([
  [Type.atom("context_3a"), Type.integer(31)],
  [Type.atom("context_3b"), Type.integer(32)],
]);

const state1 = Type.map([
  [Type.atom("state_1a"), Type.integer(101)],
  [Type.atom("state_1b"), Type.integer(102)],
]);

const state2 = Type.map([
  [Type.atom("state_2a"), Type.integer(201)],
  [Type.atom("state_2b"), Type.integer(202)],
]);

const state3 = Type.map([
  [Type.atom("state_3a"), Type.integer(301)],
  [Type.atom("state_3b"), Type.integer(302)],
]);

const struct1 = Type.componentStruct({
  emittedContext: emittedContext1,
  state: state1,
});

const struct2 = Type.componentStruct({
  emittedContext: emittedContext2,
  state: state2,
});

const struct3 = Type.componentStruct({
  emittedContext: emittedContext3,
  state: state3,
});

const entry1 = Type.map([
  [Type.atom("module"), module1],
  [Type.atom("struct"), struct1],
]);

const entry2 = Type.map([
  [Type.atom("module"), module2],
  [Type.atom("struct"), struct2],
]);

const entry3 = Type.map([
  [Type.atom("module"), module3],
  [Type.atom("struct"), struct3],
]);

describe("ComponentRegistry", () => {
  beforeEach(() => {
    ComponentRegistry.entries = Type.map([
      [cid1, entry1],
      [cid2, entry2],
    ]);
  });

  it("clear()", () => {
    assert.deepStrictEqual(
      ComponentRegistry.entries,
      Type.map([
        [cid1, entry1],
        [cid2, entry2],
      ]),
    );

    ComponentRegistry.clear();

    assert.deepStrictEqual(ComponentRegistry.entries, Type.map());
  });

  describe("getComponentEmittedContext()", () => {
    it("entry exists", () => {
      const result = ComponentRegistry.getComponentEmittedContext(cid2);
      assert.deepStrictEqual(result, emittedContext2);
    });

    it("entry doesn't exist", () => {
      const result = ComponentRegistry.getComponentEmittedContext(cid3);
      assert.isNull(result);
    });
  });

  describe("getComponentModule()", () => {
    it("entry exists", () => {
      const result = ComponentRegistry.getComponentModule(cid2);
      assert.equal(result, module2);
    });

    it("entry doesn't exist", () => {
      const result = ComponentRegistry.getComponentModule(cid3);
      assert.isNull(result);
    });
  });

  describe("getComponentState()", () => {
    it("entry exists", () => {
      const result = ComponentRegistry.getComponentState(cid2);
      assert.deepStrictEqual(result, state2);
    });

    it("entry doesn't exist", () => {
      const result = ComponentRegistry.getComponentState(cid3);
      assert.isNull(result);
    });
  });

  describe("getComponentStruct()", () => {
    it("entry exists", () => {
      const result = ComponentRegistry.getComponentStruct(cid2);
      assert.equal(result, struct2);
    });

    it("entry doesn't exist", () => {
      const result = ComponentRegistry.getComponentStruct(cid3);
      assert.isNull(result);
    });
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

  describe("isCidRegistered()", () => {
    it("is registered", () => {
      assert.isTrue(ComponentRegistry.isCidRegistered(cid2));
    });

    it("is not registered", () => {
      assert.isFalse(ComponentRegistry.isCidRegistered(cid3));
    });
  });

  it("populate()", () => {
    ComponentRegistry.populate("dummyentries");
    assert.equal(ComponentRegistry.entries, "dummyentries");
  });

  it("putEntry()", () => {
    ComponentRegistry.putEntry(cid3, entry3);

    assert.deepStrictEqual(
      ComponentRegistry.entries,
      Type.map([
        [cid1, entry1],
        [cid2, entry2],
        [cid3, entry3],
      ]),
    );
  });

  it("putComponentStruct()", () => {
    initComponentRegistryEntry(cid4);

    const componentStruct = Type.componentStruct();
    ComponentRegistry.putComponentStruct(cid4, componentStruct);

    assert.equal(ComponentRegistry.getComponentStruct(cid4), componentStruct);
  });
});
