"use strict";

import {
  assert,
  assertBoxedError,
  linkModules,
  unlinkModules,
} from "../../../support/helpers.mjs";

import AssetPathRegistry from "../../../../../assets/js/asset_path_registry.mjs";
import Elixir_Hologram_Router_Helpers from "../../../../../assets/js/elixir/hologram/router/helpers.mjs";
import Type from "../../../../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

const assetManifest = {
  "static-path-1": "/asset-path-1",
  "static-path-2": "/asset-path-2",
  "static-path-3": "/asset-path-3",
};

beforeEach(() => {
  AssetPathRegistry.hydrate(assetManifest);
});

afterEach(() => {
  AssetPathRegistry.entries = null;
});

describe("asset_path/1", () => {
  it("entry for static path exists", () => {
    const result = Elixir_Hologram_Router_Helpers["asset_path/1"](
      Type.bitstring("static-path-2"),
    );

    assert.deepStrictEqual(result, Type.bitstring("/asset-path-2"));
  });

  it("entry for static path doesn't exists", () => {
    assertBoxedError(
      () =>
        Elixir_Hologram_Router_Helpers["asset_path/1"](
          Type.bitstring("static-path-4"),
        ),
      "Hologram.AssetNotFoundError",
      'there is no such asset: "static-path-4"',
    );
  });
});
