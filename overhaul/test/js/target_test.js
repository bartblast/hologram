"use strict";

import { assert, cleanup } from "./support/commons";
beforeEach(() => cleanup())

import Runtime from "../../assets/js/hologram/runtime"
import Target from "../../assets/js/hologram/target"
import Type from "../../assets/js/hologram/type"

describe("constructor()", () => {
  it("constructs Target object", () => {
    const id = "test_id"
    const TestComponentClass = class {}
    Runtime.registerComponentClass(id, TestComponentClass)

    const result = new Target(id)

    assert.isTrue(result instanceof Target)
    assert.equal(result.id, id)
    assert.equal(result.class, TestComponentClass)
    assert.deepStrictEqual(result.module, Type.module("TestComponentClass"))
  })
})