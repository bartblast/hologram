export const assert = require("chai").assert;
export const sinon = require("sinon");

const { JSDOM } = require("jsdom");
const util = require("util");

export function debug(obj) {
  console.log(util.inspect(obj, { showHidden: false, depth: null }));
}

export function mockWindow() {
  return new JSDOM().window;
}

global.Module_Stub_1 = class Module_Stub_1 {}
global.Module_Stub_2 = class Module_Stub_2 {}