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
