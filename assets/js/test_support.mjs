"use strict";

import {assert} from "chai";
import Erlang from "./erlang/erlang.mjs";
import Hologram from "./hologram.mjs";
import sinonESM from "../node_modules/sinon/pkg/sinon-esm.js";
import Type from "./type.mjs";

export {assert} from "chai";
export const sinon = sinonESM;

export function assertBoxedFalse(boxed) {
  assert.isTrue(Type.isFalse(boxed));
}

export function assertBoxedTrue(boxed) {
  assert.isTrue(Type.isTrue(boxed));
}

export function assertFrozen(obj) {
  assert.isTrue(Object.isFrozen(obj));
}

export function assertNotFrozen(obj) {
  assert.isFalse(Object.isFrozen(obj));
}

export function linkModules() {
  globalThis.Hologram = Hologram;
  globalThis.Hologram.Erlang = Erlang;
}

export function unlinkModules() {
  delete globalThis.Hologram;
}
