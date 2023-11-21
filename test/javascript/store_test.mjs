"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";

import Store from "../../assets/js/store.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

beforeEach(() => {
  Store.data = Type.map([]);
});

afterEach(() => {
  Store.data = Type.map([]);
});

describe("getComponentContext()", () => {
  it("component data exists", () => {
    const cid = Type.bitstring("my_component_2");

    Store.data = Type.map([
      [
        Type.bitstring("my_component_1"),
        Type.map([[Type.atom("context"), "dummy_1"]]),
      ],
      [cid, Type.map([[Type.atom("context"), "dummy_2"]])],
    ]);

    const result = Store.getComponentContext(cid);

    assert.equal(result, "dummy_2");
  });

  it("component data doesn't exist", () => {
    const cid = Type.bitstring("my_component");
    const result = Store.getComponentContext(cid);

    assert.isNull(result);
  });
});

describe("getComponentData()", () => {
  it("component data exists", () => {
    const cid = Type.bitstring("my_component_2");

    Store.data = Type.map([
      [Type.bitstring("my_component_1"), "dummy_1"],
      [cid, "dummy_2"],
    ]);

    const result = Store.getComponentData(cid);

    assert.equal(result, "dummy_2");
  });

  it("component data doesn't exist", () => {
    const cid = Type.bitstring("my_component");
    const result = Store.getComponentData(cid);

    assert.isNull(result);
  });
});

it("hydrate()", () => {
  Store.data = Type.map([
    [Type.atom("a"), Type.integer(1)],
    [Type.atom("b"), Type.integer(2)],
  ]);

  Store.hydrate(
    Type.map([
      [Type.atom("c"), Type.integer(3)],
      [Type.atom("a"), Type.integer(4)],
    ]),
  );

  assert.deepStrictEqual(
    Store.data,
    Type.map([
      [Type.atom("a"), Type.integer(4)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ]),
  );
});
