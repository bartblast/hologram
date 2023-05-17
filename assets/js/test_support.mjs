"use strict";

import {assert} from "chai";

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
