export const assert = require("chai").assert;
export const sinon = require("sinon");

const { JSDOM } = require("jsdom");

export function mockWindow() {
  return new JSDOM().window;
}