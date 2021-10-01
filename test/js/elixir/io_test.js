"use strict";

import { assert, sinon } from "../support/commons"
import IO from "../../../assets/js/hologram/elixir/io";

describe("inspect()", () => {
  it("prints debug info for the given value", () => {
    const stub = sinon.stub(console, "debug");

    const val = {type: "integer", value: 1}
    IO.inspect(val)

    sinon.assert.calledWith(stub, val);
  })

  it("returns the value passed as argument", () => {
    const val = {type: "integer", value: 1}
    const result = IO.inspect(val)

    assert.equal(result, val)
  })
})
