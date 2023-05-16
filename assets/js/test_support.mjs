"use strict";

import {assert} from "chai";

export {assert} from "chai";

export function assertFrozen(obj) {
  assert.isTrue(Object.isFrozen(obj));
}
