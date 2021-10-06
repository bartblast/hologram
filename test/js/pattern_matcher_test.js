"use strict";

import { assert } from "./support/commons";
import HologramNotImplementedError from "../../assets/js/hologram/errors";
import PatternMatcher from "../../assets/js/hologram/pattern_matcher"
import Type from "../../assets/js/hologram/type"

describe("isFunctionArgsPatternMatched()", () => {
  it("returns false if number of args is different than number of params", () => {
    const params = [Type.placeholder(), Type.placeholder()]
    const args = [Type.integer(1)]
    const result = PatternMatcher.isFunctionArgsPatternMatched(params, args)

    assert.isFalse(result)
  })

  it("returns false if at least one arg doesn't match the params pattern", () => {
    const params = [Type.placeholder(), Type.atom("a")]
    const args = [Type.atom("b"), Type.atom("c")]
    const result = PatternMatcher.isFunctionArgsPatternMatched(params, args)

    assert.isFalse(result)
  })

  it("returns true if the args match the params pattern", () => {
    const params = [Type.placeholder(), Type.atom("a")]
    const args = [Type.atom("b"), Type.atom("a")]
    const result = PatternMatcher.isFunctionArgsPatternMatched(params, args)

    assert.isTrue(result)
  })
})

describe("isPatternMatched()", () => {
  it("returns true if the boxed type of left-hand-side is placeholder", () => {
    const left = Type.placeholder()
    const right = Type.integer(1)
    const result = PatternMatcher.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if the boxed type of left-hand-side is different than boxed type of right-hand-side", () => {
    const left = Type.float(1.0)
    const right = Type.integer(1)
    const result = PatternMatcher.isPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("returns true if atom boxed type left-hand-side is equal to atom boxed type right hand side", () => {
    const left = Type.atom("a")
    const right = Type.atom("a")
    const result = PatternMatcher.isPatternMatched(left, right)

    assert.isTrue(result)
  })

  it("returns false if atom boxed type left-hand-side is not equal to atom boxed type right hand side", () => {
    const left = Type.atom("a")
    const right = Type.atom("b")
    const result = PatternMatcher.isPatternMatched(left, right)

    assert.isFalse(result)
  })

  it("throws an error for not implemented boxed types", () => {
    const left = {type: "not implemented", value: "a"}
    const right = {type: "not implemented", value: "b"}
    const expectedMessage = 'PatternMatcher.isPatternMatched(): left = {"type":"not implemented","value":"a"}'

    assert.throw(() => { PatternMatcher.isPatternMatched(left, right) }, HologramNotImplementedError, expectedMessage);
  })
})