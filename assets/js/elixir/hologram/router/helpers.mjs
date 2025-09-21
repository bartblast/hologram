"use strict";

import AssetPathRegistry from "../../../asset_path_registry.mjs";
import Bitstring from "../../../bitstring.mjs";
import Interpreter from "../../../interpreter.mjs";
import Type from "../../../type.mjs";

const Elixir_Hologram_Router_Helpers = {
  "asset_path/1": (sourceAssetPath) => {
    const distAssetPath = AssetPathRegistry.lookup(sourceAssetPath);

    if (Type.isNil(distAssetPath)) {
      const message = `there is no such asset: "${Bitstring.toText(
        sourceAssetPath,
      )}"`;

      Interpreter.raiseError("Hologram.AssetNotFoundError", message);
    }

    return distAssetPath;
  },
};

export default Elixir_Hologram_Router_Helpers;
