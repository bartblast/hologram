import { assert } from "./support/commons";
import Type from "../../assets/js/hologram/type";

describe("boolean()", () => {
  it("returns boxed boolean value", () => {
    const expected = {type: "boolean", value: true}
    const result = Type.boolean(true)
    assert.deepStrictEqual(result, expected)
  })
})
