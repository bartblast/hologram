import { assert } from "../support/commons"

import Enum from "../../../assets/js/hologram/elixir/enum";
import HologramNotImplementedError from "../../../assets/js/hologram/errors";
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

  it("returns boxed true boolean value if the list contains the element", () => {
    const elem = {type: "integer", value: 2}
    const result = Enum.member$question(list, elem)
    const expected = Type.boolean(true)

    assert.deepStrictEqual(result, expected)
  })

  it("returns boxed false boolean value if the list doesn't contain the element", () => {
    const elem = {type: "integer", value: 3}
    const result = Enum.member$question(list, elem)
    const expected = Type.boolean(false)

    assert.deepStrictEqual(result, expected)
  })

  it("throws an error for not implemented enumerable types", () => {
    const enumerable = {type: "not implemented", value: "test"}
    const elem = {type: "integer", value: 1}
    const expectedMessage = 'Enum.member$question(): enumerable = {"type":"not implemented","value":"test"}, elem = {"type":"integer","value":1}'
    assert.throw(() => { Enum.member$question(enumerable, elem) }, HologramNotImplementedError, expectedMessage);
  })
})