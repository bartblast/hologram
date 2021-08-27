import { assert } from "../support/commons"

import Enum from "../../../assets/js/hologram/elixir/enum";
import Type from "../../../assets/js/hologram/type";

describe("member$question()", () => {
  let list;
  beforeEach(() => {
    list = {
      type: "list",
      data: [
        {type: "integer", value: 1},
        {type: "integer", value: 2}
      ]
    }
  })

  it("list has element", () => {
    const element = {type: "integer", value: 2}
    const result = Enum.member$question(list, element)
    const expected = Type.boolean(true)

    assert.deepStrictEqual(result, expected)
  })

  it("list doesn't have element", () => {
    const element = {type: "integer", value: 3}
    const result = Enum.member$question(list, element)
    const expected = Type.boolean(false)

    assert.deepStrictEqual(result, expected)
  })
})