"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import AssetPathRegistry from "../../assets/js/asset_path_registry.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const assetManifest = {
  "static-path-1": "/asset-path-1",
  "static-path-2": "/asset-path-2",
  "static-path-3": "/asset-path-3",
};

describe("AssetPathRegistry", () => {
  beforeEach(() => {
    AssetPathRegistry.populate(assetManifest);
  });

  describe("lookup", () => {
    it("entry for static path exists", () => {
      const result = AssetPathRegistry.lookup(Type.bitstring2("static-path-2"));
      assert.deepStrictEqual(result, Type.bitstring2("/asset-path-2"));
    });

    it("entry for static path doesn't exists", () => {
      const result = AssetPathRegistry.lookup(Type.bitstring2("static-path-4"));
      assert.deepStrictEqual(result, Type.nil());
    });
  });

  it("populate()", () => {
    AssetPathRegistry.populate(assetManifest);

    const expected = Type.map([
      [Type.bitstring2("static-path-1"), Type.bitstring2("/asset-path-1")],
      [Type.bitstring2("static-path-2"), Type.bitstring2("/asset-path-2")],
      [Type.bitstring2("static-path-3"), Type.bitstring2("/asset-path-3")],
    ]);

    assert.deepStrictEqual(AssetPathRegistry.entries, expected);
  });
});
