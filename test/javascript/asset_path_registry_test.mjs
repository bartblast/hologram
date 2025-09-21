"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import AssetPathRegistry from "../../assets/js/asset_path_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const assetManifest = {
  "source-asset-path-1": "/dist-asset-path-1",
  "source-asset-path-2": "/dist-asset-path-2",
  "source-asset-path-3": "/dist-asset-path-3",
};

describe("AssetPathRegistry", () => {
  beforeEach(() => {
    AssetPathRegistry.populate(assetManifest);
  });

  describe("lookup", () => {
    it("entry for asset path exists", () => {
      const result = AssetPathRegistry.lookup(
        Type.bitstring("source-asset-path-2"),
      );
      assert.deepStrictEqual(result, Type.bitstring("/dist-asset-path-2"));
    });

    it("entry for asset path doesn't exists", () => {
      const result = AssetPathRegistry.lookup(
        Type.bitstring("source-asset-path-4"),
      );
      assert.deepStrictEqual(result, Type.nil());
    });
  });

  it("populate()", () => {
    AssetPathRegistry.populate(assetManifest);

    const expected = Type.map([
      [
        Type.bitstring("source-asset-path-1"),
        Type.bitstring("/dist-asset-path-1"),
      ],
      [
        Type.bitstring("source-asset-path-2"),
        Type.bitstring("/dist-asset-path-2"),
      ],
      [
        Type.bitstring("source-asset-path-3"),
        Type.bitstring("/dist-asset-path-3"),
      ],
    ]);

    assert.deepStrictEqual(AssetPathRegistry.entries, expected);
  });
});
