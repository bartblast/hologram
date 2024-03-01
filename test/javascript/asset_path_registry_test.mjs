"use strict";

import {
  assert,
  linkModules,
  unlinkModules,
} from "../../assets/js/test_support.mjs";

import AssetPathRegistry from "../../assets/js/asset_path_registry.mjs";
import Type from "../../assets/js/type.mjs";
import Utils from "../../assets/js/utils.mjs";

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

it("hydrate()", () => {
  AssetPathRegistry.hydrate(assetManifest);

  const expected = Type.map([
    [Type.bitstring("static-path-1"), Type.bitstring("/asset-path-1")],
    [Type.bitstring("static-path-2"), Type.bitstring("/asset-path-2")],
    [Type.bitstring("static-path-3"), Type.bitstring("/asset-path-3")],
  ]);

  assert.deepStrictEqual(AssetPathRegistry.entries, expected);
});

describe("lookup", () => {
  it("entry for static path exists", () => {
    const result = AssetPathRegistry.lookup(Type.bitstring("static-path-2"));
    assert.deepStrictEqual(result, Type.bitstring("/asset-path-2"));
  });

  it("entry for static path doesn't exists", () => {
    const result = AssetPathRegistry.lookup(Type.bitstring("static-path-4"));
    assert.deepStrictEqual(result, Type.bitstring("/static-path-4"));
  });
});
