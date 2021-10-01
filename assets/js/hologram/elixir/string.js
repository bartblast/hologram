"use strict";

import Utils from "../utils"

export default class String {
  static to_atom(boxedString) {
    const boxedAtom = {type: "atom", value: boxedString.value}
    return Utils.freeze(boxedAtom)
  }
}