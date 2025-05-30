"use strict";

import AssetPathRegistry from "../../../asset_path_registry.mjs";
import Bitstring from "../../../bitstring.mjs";
import Interpreter from "../../../interpreter.mjs";
import Type from "../../../type.mjs";

const Elixir_Hologram_Router_Helpers = {
  "asset_path/1": (staticPath) => {
    const assetPath = AssetPathRegistry.lookup(staticPath);

    if (Type.isNil(assetPath)) {
      const message = `there is no such asset: "${Bitstring.toText(
        staticPath,
      )}"`;

      Interpreter.raiseError("Hologram.AssetNotFoundError", message);
    }

    return assetPath;
  },
};

export default Elixir_Hologram_Router_Helpers;
