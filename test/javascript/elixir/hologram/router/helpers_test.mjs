"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../../../support/helpers.mjs";

import {defineModule1Fixture} from "../../../support/fixtures/router/helpers/module_1.mjs";
import {defineModule2Fixture} from "../../../support/fixtures/router/helpers/module_2.mjs";

import AssetPathRegistry from "../../../../../assets/js/asset_path_registry.mjs";
import Elixir_Hologram_Router_Helpers from "../../../../../assets/js/elixir/hologram/router/helpers.mjs";
import Type from "../../../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

const assetManifest = {
  "static-path-1": "/asset-path-1",
  "static-path-2": "/asset-path-2",
  "static-path-3": "/asset-path-3",
};

const module1 = Type.alias("Hologram.Test.Fixtures.Router.Helpers.Module1");
const module2 = Type.alias("Hologram.Test.Fixtures.Router.Helpers.Module2");

describe("Elixir_Hologram_Router_Helpers", () => {
  before(() => {
    defineModule1Fixture();
    defineModule2Fixture();
  });

  beforeEach(() => {
    AssetPathRegistry.hydrate(assetManifest);
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

  describe("page_path/1", () => {
    const page_path = Elixir_Hologram_Router_Helpers["page_path/1"];

    it("module arg", () => {
      const result = page_path(module1);
      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module1",
      );

      assert.deepStrictEqual(result, expected);
    });

    it("tuple arg", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
      ]);

      const result = page_path(Type.tuple([module2, params]));

      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module2/abc/123",
      );

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("page_path/2", () => {
    const page_path = Elixir_Hologram_Router_Helpers["page_path/2"];

    it("valid params", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
      ]);

      const result = page_path(module2, params);

      const expected = Type.bitstring(
        "/hologram-test-fixtures-router-helpers-module2/abc/123",
      );

      assert.deepStrictEqual(result, expected);
    });

    it("missing single param", () => {
      assertBoxedError(
        () =>
          page_path(
            module2,
            Type.keywordList([[Type.atom("param_2"), Type.integer(123)]]),
          ),
        "ArgumentError",
        'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
      );
    });

    it("missing multiple params", () => {
      assertBoxedError(
        () => page_path(module2, Type.keywordList([])),
        "ArgumentError",
        'page "Hologram.Test.Fixtures.Router.Helpers.Module2" expects "param_1" param',
      );
    });

    it("extraneous single param", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
        [Type.atom("param_3"), Type.bitstring("xyz")],
      ]);

      assertBoxedError(
        () => page_path(module2, params),
        "ArgumentError",
        `page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param`,
      );
    });

    it("extraneous multiple params", () => {
      const params = Type.keywordList([
        [Type.atom("param_1"), Type.atom("abc")],
        [Type.atom("param_2"), Type.integer(123)],
        [Type.atom("param_3"), Type.bitstring("xyz")],
        [Type.atom("param_4"), Type.integer(987)],
      ]);

      assertBoxedError(
        () => page_path(module2, params),
        "ArgumentError",
        `page "Hologram.Test.Fixtures.Router.Helpers.Module2" doesn't expect "param_3" param`,
      );
    });
  });
});
