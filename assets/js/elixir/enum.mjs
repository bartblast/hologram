/*
This is only implemented to make testing easier, it is not included in the project build.
Project builds link Elixir_Enum dynamically from automatically transpiled code.
*/

"use strict";

import Hologram from "../hologram.mjs";

const Type = Hologram.Type;

const Elixir_Enum = {
  count: (enumerable) => {
    if (Type.isList(enumerable)) {
      return Erlang.length(enumerable);
    }

    if (Type.isMap(enumerable)) {
      return Type.integer(Object.keys(enumerable.data).length);
    }

    return Type.integer(enumerable.data.length);
  },
};

export default Elixir_Enum;
