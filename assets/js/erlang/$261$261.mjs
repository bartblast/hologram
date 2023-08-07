// function: :erlang.==/2
// deps: []

"use strict";

import Type from "../type.mjs";

export default (left, right) => {
  let value;

  switch (left.type) {
    case "float":
    case "integer":
      if (Type.isNumber(left) && Type.isNumber(right)) {
        value = left.value == right.value;
      } else {
        value = false;
      }
      break;

    default:
      value = left.type === right.type && left.value === right.value;
      break;
  }

  return Type.boolean(value);
};
