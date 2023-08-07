// :erlang.-/2

"use strict";

import Type from "../type.mjs";

export default (left, right) => {
  const [type, leftValue, rightValue] = Type.maybeNormalizeNumberTerms(
    left,
    right
  );

  const result = leftValue.value - rightValue.value;

  return type === "float" ? Type.float(result) : Type.integer(result);
};
