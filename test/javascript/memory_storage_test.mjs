"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import MemoryStorage from "../../assets/js/memory_storage.mjs";

describe("MemoryStorage", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  beforeEach(() => {
    MemoryStorage.data = {};
  });

  describe("get()", () => {
    it("key exists, non-falsy value", () => {
      MemoryStorage.data["my_key"] = 123;
      assert.equal(MemoryStorage.get("my_key"), 123);
    });

    it("key exists, falsy value (except null)", () => {
      MemoryStorage.data["my_key"] = false;
      assert.isFalse(MemoryStorage.get("my_key"));
    });

    it("key doesn't exists", () => {
      assert.isNull(MemoryStorage.get("my_key"));
    });
  });

  describe("put()", () => {
    MemoryStorage.put("my_key", 234);
    assert.equal(MemoryStorage.data["my_key"], 234);
  });
});
