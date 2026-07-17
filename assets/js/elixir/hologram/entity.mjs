"use strict";

import Type from "../../type.mjs";
import Utils from "../../utils.mjs";

const Elixir_Hologram_Entity = {
  "generate_id/0": () => Type.bitstring(Utils.uuidv7()),
};

export default Elixir_Hologram_Entity;
