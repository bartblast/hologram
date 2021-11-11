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
}