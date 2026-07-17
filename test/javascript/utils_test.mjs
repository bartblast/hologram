"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "./support/helpers.mjs";

import Utils from "../../assets/js/utils.mjs";

defineGlobalErlangAndElixirModules();

describe("Utils", () => {
  describe("capitalize()", () => {
    it("empty string", () => {
      assert.equal(Utils.capitalize(""), "");
    });

    it("single-word string", () => {
      assert.equal(Utils.capitalize("aaa"), "Aaa");
    });

    it("multiple-word string", () => {
      assert.equal(Utils.capitalize("aaa bbb"), "Aaa bbb");
    });
  });

  describe("chunkArray()", () => {
    it("empty array", () => {
      const result = Utils.chunkArray([], 3);
      assert.deepStrictEqual(result, []);
    });

    it("array can be chunked into equal parts", () => {
      const result = Utils.chunkArray([1, 2, 3, 4, 5, 6, 7, 8, 9], 3);

      assert.deepStrictEqual(result, [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ]);
    });

    it("array can't be chunked into equal parts", () => {
      const result = Utils.chunkArray([1, 2, 3, 4, 5, 6, 7, 8], 3);

      assert.deepStrictEqual(result, [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8],
      ]);
    });
  });

  describe("concatUint8Arrays()", () => {
    it("concatenates multiple 8-bit unsigned integer arrays", () => {
      const arrays = [
        new Uint8Array([1]),
        new Uint8Array([2, 3]),
        new Uint8Array([4, 5, 6]),
      ];
      const result = Utils.concatUint8Arrays(arrays);
      const expected = new Uint8Array([1, 2, 3, 4, 5, 6]);

      assert.deepStrictEqual(result, expected);
    });
  });

  describe("naiveNounPlural", () => {
    it("0", () => {
      const result = Utils.naiveNounPlural("car", 0);
      assert.equal(result, "cars");
    });

    it("1", () => {
      const result = Utils.naiveNounPlural("car", 1);
      assert.equal(result, "car");
    });

    it("2", () => {
      const result = Utils.naiveNounPlural("car", 2);
      assert.equal(result, "cars");
    });

    it("3", () => {
      const result = Utils.naiveNounPlural("car", 3);
      assert.equal(result, "cars");
    });
  });

  describe("ordinal", () => {
    it("1st", () => {
      assert.equal(Utils.ordinal(1), "1st");
    });

    it("2nd", () => {
      assert.equal(Utils.ordinal(2), "2nd");
    });

    it("3rd", () => {
      assert.equal(Utils.ordinal(3), "3rd");
    });

    it("4th", () => {
      assert.equal(Utils.ordinal(4), "4th");
    });

    it("15th", () => {
      assert.equal(Utils.ordinal(15), "15th");
    });

    it("21st", () => {
      assert.equal(Utils.ordinal(21), "21st");
    });
  });

  describe("randomUUID()", () => {
    const uuidV4Regex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

    it("delegates to crypto.randomUUID() when available", () => {
      const result = Utils.randomUUID();

      assert.match(result, uuidV4Regex);
    });

    it("falls back to a generated UUID when crypto.randomUUID() is unavailable", () => {
      const original = crypto.randomUUID;
      crypto.randomUUID = undefined;

      try {
        const result = Utils.randomUUID();
        assert.match(result, uuidV4Regex);
      } finally {
        crypto.randomUUID = original;
      }
    });
  });

  it("randomUint32()", () => {
    const result = Utils.randomUint32();

    assert.isTrue(Number.isInteger(result));
    assert.isAtLeast(result, 0);
    assert.isAtMost(result, 4_294_967_295);
  });

  it("runAsyncTask()", async () => {
    const obj = {a: 1, b: 2};
    const task = () => (obj.b = 3);

    const promise = Utils.runAsyncTask(task);
    assert.instanceOf(promise, Promise);

    assert.equal(obj.b, 2);

    await promise;

    assert.equal(obj.b, 3);
  });

  it("shallowCloneArray()", () => {
    const arr = [1, [3, 4]];
    const clone = Utils.shallowCloneArray(arr);

    assert.deepStrictEqual(clone, [1, [3, 4]]);

    clone[0] = 10;
    clone[1][0] = 30;

    assert.deepStrictEqual(arr, [1, [30, 4]]);
    assert.deepStrictEqual(clone, [10, [30, 4]]);
  });

  it("shallowCloneObject()", () => {
    const obj = {a: 1, b: {c: 3, d: 4}};
    const clone = Utils.shallowCloneObject(obj);

    assert.deepStrictEqual(clone, {a: 1, b: {c: 3, d: 4}});

    clone.a = 10;
    clone.b.c = 30;

    assert.deepStrictEqual(obj, {a: 1, b: {c: 30, d: 4}});
    assert.deepStrictEqual(clone, {a: 10, b: {c: 30, d: 4}});
  });

  // IMPORTANT!
  // Each test in this describe block has a related Elixir test in test/elixir/hologram/entity_test.exs (describe "generate_id/0")
  // Always update both together.
  describe("uuidv7()", () => {
    it("returns a version 7 UUID string", () => {
      assert.match(
        Utils.uuidv7(),
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    });

    it("returns a different UUID on each call", () => {
      assert.notEqual(Utils.uuidv7(), Utils.uuidv7());
    });

    it("embeds the number of milliseconds since the Unix epoch in the leading bits", () => {
      const unixMsBefore = Date.now();
      const uuid = Utils.uuidv7();
      const unixMsAfter = Date.now();

      const embeddedUnixMs = parseInt(
        uuid.replaceAll("-", "").slice(0, 12),
        16,
      );

      assert.isAtLeast(embeddedUnixMs, unixMsBefore);
      assert.isAtMost(embeddedUnixMs, unixMsAfter);
    });
  });
});
