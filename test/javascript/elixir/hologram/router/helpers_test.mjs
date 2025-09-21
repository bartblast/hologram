"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../../../support/helpers.mjs";

import AssetPathRegistry from "../../../../../assets/js/asset_path_registry.mjs";
import Elixir_Hologram_Router_Helpers from "../../../../../assets/js/elixir/hologram/router/helpers.mjs";
import Type from "../../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const assetManifest = {
  "source-asset-path-1": "/dist-asset-path-1",
  "source-asset-path-2": "/dist-asset-path-2",
  "source-asset-path-3": "/dist-asset-path-3",
};

describe("Elixir_Hologram_Router_Helpers", () => {
  beforeEach(() => {
    AssetPathRegistry.populate(assetManifest);
  });

  describe("asset_path/1", () => {
    const asset_path = Elixir_Hologram_Router_Helpers["asset_path/1"];

    it("entry for asset path exists", () => {
      const result = asset_path(Type.bitstring("source-asset-path-2"));
      assert.deepStrictEqual(result, Type.bitstring("/dist-asset-path-2"));
    });

    it("entry for asset path doesn't exists", () => {
      assertBoxedError(
        () => asset_path(Type.bitstring("source-asset-path-4")),
        "Hologram.AssetNotFoundError",
        'there is no such asset: "source-asset-path-4"',
      );
    });
  });
});
