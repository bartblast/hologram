"use strict";

import { assert, assertBoxedFalse, cleanup } from "../../support/commons"
beforeEach(() => cleanup());

import Changeset from "../../../../assets/js/hologram/elixir/ecto/changeset";
import Map from "../../../../assets/js/hologram/elixir/map";
import Type from "../../../../assets/js/hologram/type";

describe("cast()", () => {
  let data, result;

  beforeEach(() => {
    data = Type.map()
    data = Map.put(data, Type.atom("a"), Type.integer(1))
    data = Map.put(data, Type.atom("b"), Type.integer(2))

    let types = Type.map()
    types = Map.put(types, Type.atom("k"), Type.atom("integer"))
    types = Map.put(types, Type.atom("l"), Type.atom("string"))
    types = Map.put(types, Type.atom("m"), Type.atom("integer"))
    types = Map.put(types, Type.atom("n"), Type.atom("float"))

    let params = Type.map()
    params = Map.put(params, Type.atom("k"), Type.integer(9))
    params = Map.put(params, Type.atom("l"), Type.integer(8))
    params = Map.put(params, Type.atom("m"), Type.integer(7))
    params = Map.put(params, Type.atom("n"), Type.string("test_string"))
    params = Map.put(params, Type.atom("o"), Type.atom("test_atom"))

    const permitted = Type.list([
      Type.atom("k"),
      Type.atom("l"),
      Type.atom("m"),
      Type.atom("n")
    ])

    result = Changeset.cast(Type.tuple([data, types]), params, permitted)
  })

  it("sets action field", () => {
    const actionField = Map.get(result, Type.atom("action"))
    assert.deepStrictEqual(actionField, Type.nil())
  })

  it("sets changes field", () => {
    let expected = Type.map()
    expected = Map.put(expected, Type.atom("k"), Type.integer(9))
    expected = Map.put(expected, Type.atom("m"), Type.integer(7))

    const changesField = Map.get(result, Type.atom("changes"))

    assert.deepStrictEqual(changesField, expected)
  })

  it("sets data field", () => {
    const dataField = Map.get(result, Type.atom("data"))
    assert.deepStrictEqual(dataField, data)
  })

  it("sets errors field", () => {
    const expected = Type.list([
      Type.tuple([
        Type.atom("l"),
        Type.tuple([
          Type.string("is invalid"),
          Type.list([
            Type.tuple([Type.atom("type"), Type.atom("string")]),
            Type.tuple([Type.atom("validation"), Type.atom("cast")])
          ])
        ])
      ]),
      Type.tuple([
        Type.atom("n"),
        Type.tuple([
          Type.string("is invalid"),
          Type.list([
            Type.tuple([Type.atom("type"), Type.atom("float")]),
            Type.tuple([Type.atom("validation"), Type.atom("cast")])
          ])
        ])
      ]),
    ])

    const errorsField = Map.get(result, Type.atom("errors"))
    assert.deepStrictEqual(errorsField, expected)
  })

  it("sets valid? field in valid changeset", () => {
    const validField = Map.get(result, Type.atom("valid?"))
    assertBoxedFalse(validField)
  })
})

describe("validate_required()", () => {
  let data, permitted, types;

  beforeEach(() => {
    data = Type.map()

    types = Type.map()
    types = Map.put(types, Type.atom("a"), Type.atom("string"))
    types = Map.put(types, Type.atom("b"), Type.atom("integer"))

    permitted = Type.list([
      Type.atom("a"),
      Type.atom("b"),
    ])
  })

  it("doesn't add any errors if all required fields are present", () => {
    let params = Type.map()
    params = Map.put(params, Type.atom("a"), Type.string("test"))
    params = Map.put(params, Type.atom("b"), Type.integer(123))

    let changeset = Changeset.cast(Type.tuple([data, types]), params, permitted)
    const fields = Type.list([Type.atom("a"), Type.atom("b")])
    changeset = Changeset.validate_required(changeset, fields)

    const errors = Map.get(changeset, Type.atom("errors"))

    assert.deepStrictEqual(errors, Type.list())
  })

  it("adds required error if a required field is not in params", () => {
    let params = Type.map()
    params = Map.put(params, Type.atom("b"), Type.integer(123))

    let changeset = Changeset.cast(Type.tuple([data, types]), params, permitted)
    const fields = Type.list([Type.atom("a"), Type.atom("b")])
    changeset = Changeset.validate_required(changeset, fields)

    const errors = Map.get(changeset, Type.atom("errors"))

    const expected = Type.list([
      Type.tuple([
        Type.atom("a"),
        Type.tuple([
          Type.string("can't be blank"),
          Type.list([
            Type.tuple([Type.atom("validation"), Type.atom("required")])
          ])
        ])
      ]),
    ])

    assert.deepStrictEqual(errors, expected)
  })

  it("adds required error if a required field is a blank string", () => {
    let params = Type.map()
    params = Map.put(params, Type.atom("a"), Type.string(""))
    params = Map.put(params, Type.atom("b"), Type.integer(123))

    let changeset = Changeset.cast(Type.tuple([data, types]), params, permitted)
    const fields = Type.list([Type.atom("a"), Type.atom("b")])
    changeset = Changeset.validate_required(changeset, fields)

    const errors = Map.get(changeset, Type.atom("errors"))

    const expected = Type.list([
      Type.tuple([
        Type.atom("a"),
        Type.tuple([
          Type.string("can't be blank"),
          Type.list([
            Type.tuple([Type.atom("validation"), Type.atom("required")])
          ])
        ])
      ]),
    ])

    assert.deepStrictEqual(errors, expected)
  })

  it("handles multiple required errors", () => {
    let params = Type.map()

    let changeset = Changeset.cast(Type.tuple([data, types]), params, permitted)
    const fields = Type.list([Type.atom("a"), Type.atom("b")])
    changeset = Changeset.validate_required(changeset, fields)

    const errors = Map.get(changeset, Type.atom("errors"))

    const expected = Type.list([
      Type.tuple([
        Type.atom("a"),
        Type.tuple([
          Type.string("can't be blank"),
          Type.list([
            Type.tuple([Type.atom("validation"), Type.atom("required")])
          ])
        ])
      ]),
      Type.tuple([
        Type.atom("b"),
        Type.tuple([
          Type.string("can't be blank"),
          Type.list([
            Type.tuple([Type.atom("validation"), Type.atom("required")])
          ])
        ])
      ]),
    ])

    assert.deepStrictEqual(errors, expected)
  })
})