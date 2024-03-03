"use strict";

import AssetPathRegistry from "../../../asset_path_registry.mjs";
import Bitstring from "../../../bitstring.mjs";
import Type from "../../../type.mjs";

const Elixir_Hologram_Router_Helpers = {
  "asset_path/1": (staticPath) => {
    const assetPath = AssetPathRegistry.lookup(staticPath);

    return !Type.isNil(assetPath)
      ? assetPath
      : Bitstring.merge([Type.bitstring("/"), staticPath]);
  },
};

export default Elixir_Hologram_Router_Helpers;
