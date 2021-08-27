import { assert } from "../support/commons"
import Enum from "../../../assets/js/hologram/elixir/enum";

describe("member$question()", () => {
  it("list has element", () => {
    const list = {
      type: "list",
      data: [
        {type: "integer", value: 1},
        {type: "integer", value: 2}
      ]
    }

    const element = {type: "integer", value: 2}

    const result = Enum.member$question(list, element)
    const expected = {type: "boolean", value: true}

    assert.deepStrictEqual(result, expected)
  })

  it("list doesn't have element", () => {
    const list = {
      type: "list",
      data: [
        {type: "integer", value: 1},
        {type: "integer", value: 2}
      ]
    }

    const element = {type: "integer", value: 3}

    const result = Enum.member$question(list, element)
    const expected = {type: "boolean", value: false}

    assert.deepStrictEqual(result, expected)
  })
})