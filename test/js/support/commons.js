import Type from "../../../assets/js/hologram/type"

export const assert = require("chai").assert;
export const sinon = require("sinon");

const { JSDOM } = require("jsdom");
const util = require("util");

export function assertFreezed(obj) {
  assert.throw(() => {obj.__freezeTest__ = 1}, TypeError, /object is not extensible/);
}

export function debug(obj) {
  console.log(util.inspect(obj, { showHidden: false, depth: null }));
}

export function mockWindow() {
  return new JSDOM().window;
}

global.ModuleStub1 = class ModuleStub1 {
  static test(arg1, arg2) {
    return Type.integer(arg1.value + arg2.value)
  }
}