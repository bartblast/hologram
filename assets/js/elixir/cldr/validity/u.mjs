"use strict";

import HologramInterpreterError from "../../../errors/interpreter_error.mjs";

const Elixir_Cldr_Validity_U = {
  // {Cldr.Validity.U, :encode_key, 2} transpiles to a huge, deeply nested JS code,
  // so only a placeholder which raises an error is used here instead.
  "encode_key/2": (_key, _value) => {
    throw new HologramInterpreterError(
      "{Cldr.Validity.U, :encode_key, 2} is not supported in Hologram.\n" +
        "See what to do here: https://www.hologram.page/TODO",
    );
  },
};

export default Elixir_Cldr_Validity_U;
