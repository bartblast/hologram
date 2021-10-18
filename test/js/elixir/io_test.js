"use strict";

import { assert, sinon } from "../support/commons";
import IO from "../../../assets/js/hologram/elixir/io";
import Type from "../../../assets/js/hologram/type";

describe("inspect()", () => {
  it("prints debug info for the given value", () => {
    const stub = sinon.stub(console, "debug");

    const val = 123;
    IO.inspect(val);

    sinon.assert.calledWith(stub, val);
  });

  it("returns the value passed as argument", () => {
    const val = Type.integer(1);
    const result = IO.inspect(val);

    assert.equal(result, val);
  });
});
