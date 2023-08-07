// function: :erlang./=/2
// deps: [:erlang.==/2]

"use strict";

import Type from "../type.mjs";

export default (left, right) => {
  // Erlang.$261$261 -> :erlang.==/2
  const isEqual = Erlang.$261$261(left, right);

  return Type.boolean(Type.isFalse(isEqual));
};
