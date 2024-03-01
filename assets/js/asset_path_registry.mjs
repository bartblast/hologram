"use strict";

import Type from "./type.mjs";

export default class AssetPathRegistry {
  static entries = null;

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

  static lookup(staticPath) {
    return Erlang_Maps["get/3"](
      staticPath,
      AssetPathRegistry.entries,
      Type.nil(),
    );
  }
}
