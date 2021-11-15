"use strict";

import Enum from "../../elixir/enum";
import Keyword from "../../elixir/keyword";
import Map from "../../elixir/map";
import Type from "../../type";

export default class Changeset {
  // DEFER: implement other arg types
  static cast(arg, params, permitted, opts = Type.list()) {
    if (Type.isTuple(arg)) {
      return Changeset._castSchemaless(arg.data[0], arg.data[1], params, permitted, opts)
    }
  }

  // DEFER: handle opts param
  static _appendAcceptanceError(errors, field, _opts = Type.list()) {
    const errorInfo = Type.tuple([
      Type.string("must be accepted"),
      Type.list([
        Type.tuple([Type.atom("validation"), Type.atom("acceptance")]),
      ])
    ])

    const error = Type.tuple([field, errorInfo])

    return Enum.concat(errors, Type.list([error]))
  }

  static _appendCastError(errors, key, type) {
    const errorInfo = Type.tuple([
      Type.string("is invalid"),
      Type.list([
        Type.tuple([Type.atom("type"), Type.atom(type.value)]),
        Type.tuple([Type.atom("validation"), Type.atom("cast")]),
      ])
    ])

    const error = Type.tuple([key, errorInfo])

    return Enum.concat(errors, Type.list([error]))
  }

  static _castSchemaless(data, types, params, permitted, _opts) {
    let changeset = Type.struct("Elixir_Ecto_Changeset")
    changeset = Map.put(changeset, Type.atom("action"), Type.nil())
    changeset = Map.put(changeset, Type.atom("data"), data)
    changeset = Changeset._putErrorsField(changeset, types, params, permitted)
    changeset = Changeset._putValidField(changeset)
    changeset = Changeset._putChangesField(changeset, params, permitted)

    return changeset
  }

  static _putChangesField(changeset, params, permitted) {
    let changes = Type.map()

    Map.keys(params).data.forEach(key => {
      if (Enum.member$question(permitted, key).value) {
        const errors = Map.get(changeset, Type.atom("errors"))
        if (!Keyword.has_key$question(errors, key).value) {
          const value = Map.get(params, key)
          changes = Map.put(changes, key, value)
        }
      }
    })

    return Map.put(changeset, Type.atom("changes"), changes)
  }

  static _putErrorsField(changeset, types, params, permitted) {
    let errors = Type.list()

    Map.keys(params).data.forEach(key => {
      if (Enum.member$question(permitted, key).value) {
        const value = Map.get(params, key)
        const type = Map.get(types, key)

        if (value.type !== type.value) {
          errors = Changeset._appendCastError(errors, key, type)
        }
      }
    })

    return Map.put(changeset, Type.atom("errors"), errors)
  }

  static _putValidField(changeset) {
    const errors = Map.get(changeset, Type.atom("errors"))
    const value = Type.boolean(errors.data.length === 0)

    return Map.put(changeset, Type.atom("valid?"), value)
  }

  static validate_acceptance(changeset, field) {
    let errors = Map.get(changeset, Type.atom("errors"))
    const changes = Map.get(changeset, Type.atom("changes"))

    const boxedVal = Map.get(changes, field)
    if (boxedVal.type !== "boolean" || boxedVal.value !== true) {
      errors = Changeset._appendAcceptanceError(errors, field)
    }

    changeset = Map.put(changeset, Type.atom("errors"), errors)
    const isValid = Type.boolean(errors.data.length === 0)

    return Map.put(changeset, Type.atom("valid?"), isValid)
  }

  // DEFER: handle atom fields param (at the moment only list fields param is handled)
  static validate_required(changeset, fields) {
    let errors = Map.get(changeset, Type.atom("errors"))
    const changes = Map.get(changeset, Type.atom("changes"))

    fields.data.forEach(key => {
      const boxedVal = Map.get(changes, key)
      if (boxedVal.type === "nil" || (boxedVal.type === "string" && boxedVal.value === "")) {
        errors = Changeset._appendRequiredError(errors, key)
      }
    })

    changeset = Map.put(changeset, Type.atom("errors"), errors)
    const isValid = Type.boolean(errors.data.length === 0)

    return Map.put(changeset, Type.atom("valid?"), isValid)
  }

  static _appendRequiredError(errors, key) {
    const errorInfo = Type.tuple([
      Type.string("can't be blank"),
      Type.list([
        Type.tuple([Type.atom("validation"), Type.atom("required")]),
      ])
    ])

    const error = Type.tuple([key, errorInfo])

    return Enum.concat(errors, Type.list([error]))
  }
}