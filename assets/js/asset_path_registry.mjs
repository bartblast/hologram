"use strict";

import Type from "./type.mjs";

export default class AssetPathRegistry {
  static entries = null;

  // Deps: [:maps.get/3]
  static lookup(sourceAssetPath) {
    return Erlang_Maps["get/3"](
      sourceAssetPath,
      AssetPathRegistry.entries,
      Type.nil(),
    );
  }

  // Deps: [:maps.put/3]
  static populate(assetManifest) {
    AssetPathRegistry.entries = Type.map();

    for (const [sourceAssetPath, distAssetPath] of Object.entries(
      assetManifest,
    )) {
      const key = Type.bitstring(sourceAssetPath);
      const value = Type.bitstring(distAssetPath);

      AssetPathRegistry.entries = Erlang_Maps["put/3"](
        key,
        value,
        AssetPathRegistry.entries,
      );
    }
  }
}
