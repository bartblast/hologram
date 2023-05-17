"use strict";

import { assert } from "../../assets/js/test_support.mjs";
import StringUtils from "../../assets/js/string_utils.mjs";

describe("wrap()", () => {
  it("prepends 'left' substring and appends 'right' substring to the given string", () => {
    const result = StringUtils.wrap("ab", "cd", "ef");
    assert.equal(result, "cdabef");
  });
});
