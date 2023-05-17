"use strict";

import {assert} from "../../../assets/js/test_support.mjs";
import erlang from "../../../assets/js/erlang/erlang.mjs";
import Type from "../../../assets/js/type.mjs";

describe("is_number/1", () => {
  it("delegates to runtime Type.isNumber/1", () => {
    const result = erlang.is_number(Type.integer(123))

    assert.isTrue(result)
  })
})