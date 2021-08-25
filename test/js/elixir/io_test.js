import { sinon } from "../support/commons"
import IO from "../../../assets/js/hologram/elixir/io";

describe("inspect()", () => {
  it("prints debug info for the given value", () => {
    const stub = sinon.stub(console, "debug");

    const value = {type: "integer", value: 1}
    IO.inspect(value)

    sinon.assert.calledWith(stub, value);
  })
})
