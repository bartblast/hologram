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
