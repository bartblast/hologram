"use strict";

import {assert} from "chai";
import Type from "./type.mjs";

export {assert} from "chai";

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
