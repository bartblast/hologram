"use strict";

import Type from "./type.mjs";

export default class AssetPathRegistry {
  static entries = null;

  // The manifest the entries were populated from, by static path, as plain strings.
  static manifest = null;

  // Deps: [:maps.get/3]
  static lookup(staticPath) {
    return Erlang_Maps["get/3"](
      staticPath,
      AssetPathRegistry.entries,
      Type.nil(),
    );
  }

  // Deps: [:maps.put/3]
  static populate(assetManifest) {
    AssetPathRegistry.entries = Type.map();
    AssetPathRegistry.manifest = assetManifest;

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

  // Replaces the entries of the app's assets with the given ones, and keeps the entries of
  // Hologram's own bundles, keyed under hologram/, which name the bundles this document loaded.
  static replaceAppEntries(appAssetManifest) {
    const bundleEntries = Object.entries(AssetPathRegistry.manifest).filter(
      ([staticPath]) => staticPath.startsWith("hologram/"),
    );

    AssetPathRegistry.populate({
      ...Object.fromEntries(bundleEntries),
      ...appAssetManifest,
    });
  }
}
