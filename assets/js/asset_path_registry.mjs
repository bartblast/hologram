"use strict";

import Type from "./type.mjs";

export default class AssetPathRegistry {
  static entries = null;

  // deps: [:maps.put/3]
  static hydrate(assetManifest) {
    AssetPathRegistry.entries = Type.map([]);

    for (const [staticPath, assetPath] of Object.entries(assetManifest)) {
      const key = Type.bitstring(staticPath);
      const value = Type.bitstring(assetPath);

      AssetPathRegistry.entries = Erlang_Maps["put/3"](
        key,
        value,
        AssetPathRegistry.entries,
      );
    }
  }

  // deps: [:maps.get/3]
  static lookup(staticPath) {
    return Erlang_Maps["get/3"](
      staticPath,
      AssetPathRegistry.entries,
      Type.nil(),
    );
  }
}
