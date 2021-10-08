"use strict";

import Type from "../../../assets/js/hologram/type"
import Utils from "../../../assets/js/hologram/utils"

export const assert = require("chai").assert;
export const sinon = require("sinon");

const { JSDOM } = require("jsdom");
const util = require("util");

export function assertBoxedFalse(boxedValue) {
  assert.isTrue(Type.isFalse(boxedValue))
}

export function assertBoxedTrue(boxedValue) {
  assert.isTrue(Type.isTrue(boxedValue))
}

export function assertFrozen(obj) {
  assert.isTrue(Object.isFrozen(obj))
}

export function assertNotFrozen(obj) {
  assert.isFalse(Object.isFrozen(obj))
}

export function debug(obj) {
  console.log(util.inspect(obj, { showHidden: false, depth: null }));
}

export function fixtureOperationParamsKeyword() {
  const paramsTuples = [
    Type.tuple([Type.atom("a"), Type.integer(1)]),
    Type.tuple([Type.atom("b"), Type.integer(2)])
  ]

  return Type.list(paramsTuples)
}

export function fixtureOperationParamsMap() {
  const operationParamsKeyword = fixtureOperationParamsKeyword()
  return Type.keywordToMap(operationParamsKeyword)
}

export function fixtureOperationSpecExpressionNode(specElems) {
  const callback = (_$state) => { return Type.tuple(specElems) }
  const expressionNodeSpec = {type: "expression", callback: callback}

  return Utils.freeze(expressionNodeSpec)
}

export function mockWindow() {
  return new JSDOM().window;
}

global.ModuleStub1 = class ModuleStub1 {
  static test(arg1, arg2) {
    return Type.integer(arg1.value + arg2.value)
  }
}