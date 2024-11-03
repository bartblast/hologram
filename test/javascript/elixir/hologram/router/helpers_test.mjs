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
  "static-path-1": "/asset-path-1",
  "static-path-2": "/asset-path-2",
  "static-path-3": "/asset-path-3",
};

describe("Elixir_Hologram_Router_Helpers", () => {
  beforeEach(() => {
    AssetPathRegistry.populate(assetManifest);
  });

  describe("asset_path/1", () => {
    const asset_path = Elixir_Hologram_Router_Helpers["asset_path/1"];

    it("entry for static path exists", () => {
      const result = asset_path(Type.bitstring("static-path-2"));
      assert.deepStrictEqual(result, Type.bitstring("/asset-path-2"));
    });

    it("entry for static path doesn't exists", () => {
      assertBoxedError(
        () => asset_path(Type.bitstring("static-path-4")),
        "Hologram.AssetNotFoundError",
        'there is no such asset: "static-path-4"',
      );
    });
  });
});
