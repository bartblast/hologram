"use strict";

import {assert, defineRuntimeGlobals, sinon} from "./support/helpers.mjs";

import Utils from "../../assets/js/utils.mjs";

defineRuntimeGlobals();

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

  describe("stringify()", () => {
    it("writes a BigInt as its digits", () => {
      assert.equal(
        Utils.stringify({a: [9007199254740993n], b: 1}),
        '{"a":["9007199254740993"],"b":1}',
      );
    });

    it("answers undefined for what JSON can't write", () => {
      assert.isUndefined(Utils.stringify(undefined));
    });

    it("leaves a lone surrogate as JSON escapes it", () => {
      assert.equal(Utils.stringify("a\uD800b"), '"a\\ud800b"');
    });
  });

  describe("stringifyWellFormed()", () => {
    it("writes a BigInt as its digits", () => {
      assert.equal(
        Utils.stringifyWellFormed({a: [9007199254740993n], b: 1}),
        '{"a":["9007199254740993"],"b":1}',
      );
    });

    it("writes a lone surrogate as U+FFFD, at any depth", () => {
      assert.deepStrictEqual(
        JSON.parse(
          Utils.stringifyWellFormed({a: ["x\uD800"], b: {c: "\uDC00y"}}),
        ),
        {a: ["x\uFFFD"], b: {c: "\uFFFDy"}},
      );
    });

    it("keeps a whole surrogate pair", () => {
      assert.equal(
        JSON.parse(Utils.stringifyWellFormed("a\u{1F600}b")),
        "a\u{1F600}b",
      );
    });
  });

  // IMPORTANT!
  // Each test in this describe block has a related Elixir test in test/elixir/hologram/entity_test.exs (describe "generate_id/0")
  // Always update both together.
  describe("entityId()", () => {
    it("returns 22 base62 characters holding the bits of a version 7 UUID", () => {
      const id = Utils.entityId();

      assert.match(id, /^[0-9A-Za-z]{22}$/);

      assert.match(
        Utils.entityIdToUuid(id),
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    });

    it("returns a different id on each call", () => {
      assert.notEqual(Utils.entityId(), Utils.entityId());
    });

    it("embeds the number of milliseconds since the Unix epoch in the leading bits", () => {
      const unixMsBefore = Date.now();
      const id = Utils.entityId();
      const unixMsAfter = Date.now();

      const embeddedUnixMs = parseInt(
        Utils.entityIdToUuid(id).replaceAll("-", "").slice(0, 12),
        16,
      );

      assert.isAtLeast(embeddedUnixMs, unixMsBefore);
      assert.isAtMost(embeddedUnixMs, unixMsAfter);
    });

    it("returns ids that sort as strings in the order they were made, across milliseconds", () => {
      const ids = Array.from({length: 3}, () => {
        const id = Utils.entityId();
        const until = Date.now() + 2;

        while (Date.now() < until) {
          // Waits 2 milliseconds, as the server's twin sleeps.
        }

        return id;
      });

      assert.deepEqual([...ids].sort(), ids);
    });

    // The server has no twin for these: its ids are ordered only across milliseconds.
    // The generator is shared with uuidv7(), so each test waits for the real clock to pass the
    // frozen millisecond, and the uuidv7() tests after it start from the real time.
    describe("with the clock frozen", () => {
      let nowMs;
      let timers;

      afterEach(() => {
        timers.restore();

        while (Date.now() <= nowMs) {
          // Waits a few milliseconds.
        }
      });

      it("returns ids that sort as strings in the order of the calls within one millisecond", () => {
        nowMs = Date.now() + 5;
        timers = sinon.useFakeTimers(nowMs);

        const ids = Array.from({length: 100}, () => Utils.entityId());

        assert.isTrue(
          ids.every((id, index) => index === 0 || ids[index - 1] < id),
        );
      });

      it("shares its order with uuidv7()", () => {
        nowMs = Date.now() + 5;
        timers = sinon.useFakeTimers(nowMs);

        const first = Utils.entityIdToUuid(Utils.entityId());
        const second = Utils.uuidv7();
        const third = Utils.entityIdToUuid(Utils.entityId());

        assert.isTrue(first < second);
        assert.isTrue(second < third);
      });
    });
  });

  // IMPORTANT!
  // Each test in this describe block has a related Elixir test in test/elixir/hologram/entity_test.exs (describe "id_to_uuid/1")
  // Always update both together.
  describe("entityIdToUuid()", () => {
    it("returns the 36-character spelling of the same number", () => {
      assert.equal(
        Utils.entityIdToUuid("02y9GOZb4QYpMlaccFSmK2"),
        "0192f3a0-7b1e-7c2d-9a4b-1f2e3d4c5b6a",
      );
    });

    it("converts the smallest and the largest id", () => {
      assert.equal(
        Utils.entityIdToUuid("0000000000000000000000"),
        "00000000-0000-0000-0000-000000000000",
      );

      assert.equal(
        Utils.entityIdToUuid("7n42DGM5Tflk9n8mt7Fhc7"),
        "ffffffff-ffff-ffff-ffff-ffffffffffff",
      );
    });
  });

  describe("entityIdFromBytes()", () => {
    it("returns the entity id spelling of the bytes' number", () => {
      const bytes = Uint8Array.from(
        "0192f3a07b1e7c2d9a4b1f2e3d4c5b6a".match(/../g),
        (byte) => parseInt(byte, 16),
      );

      assert.equal(Utils.entityIdFromBytes(bytes), "02y9GOZb4QYpMlaccFSmK2");
    });

    it("converts the smallest and the largest number", () => {
      assert.equal(
        Utils.entityIdFromBytes(new Uint8Array(16)),
        "0000000000000000000000",
      );

      assert.equal(
        Utils.entityIdFromBytes(new Uint8Array(16).fill(255)),
        "7n42DGM5Tflk9n8mt7Fhc7",
      );
    });

    it("is undone by entityIdToUuid()", () => {
      const id = Utils.entityId();
      const hex = Utils.entityIdToUuid(id).replaceAll("-", "");
      const bytes = Uint8Array.from(hex.match(/../g), (byte) =>
        parseInt(byte, 16),
      );

      assert.equal(Utils.entityIdFromBytes(bytes), id);
    });
  });

  describe("isEntityId()", () => {
    it("accepts 22 base62 characters up to the largest 128-bit number", () => {
      for (const value of [
        "0000000000000000000000",
        "02wLIRxqmq3AUo6vl2OW37",
        "7n42DGM5Tflk9n8mt7Fhc7",
      ]) {
        assert.isTrue(Utils.isEntityId(value), value);
      }
    });

    it("refuses anything else", () => {
      for (const value of [
        "02wLIRxqmq3AUo6vl2OW3",
        "02wLIRxqmq3AUo6vl2OW377",
        "02wLIRxqmq3AUo6vl2OW3-",
        "02wLIRxqmq3AUo6vl2OW37\n",
        "7n42DGM5Tflk9n8mt7Fhc8",
        "zzzzzzzzzzzzzzzzzzzzzz",
        "018f0000-0000-7000-8000-000000000001",
        7,
        null,
      ]) {
        assert.isFalse(Utils.isEntityId(value), String(value));
      }
    });
  });

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

    // The clock is frozen a few milliseconds ahead, so that each test starts a new millisecond and
    // the real clock passes it again right after.
    describe("with the clock frozen", () => {
      let timers;

      const embeddedMs = (uuid) =>
        parseInt(uuid.replaceAll("-", "").slice(0, 12), 16);

      const strictlyIncreasing = (uuids) =>
        uuids.every((uuid, index) => index === 0 || uuids[index - 1] < uuid);

      afterEach(() => {
        timers.restore();
      });

      it("returns UUIDs in the order of the calls within one millisecond", () => {
        const nowMs = Date.now() + 5;
        timers = sinon.useFakeTimers(nowMs);

        const uuids = Array.from({length: 100}, () => Utils.uuidv7());

        assert.isTrue(strictlyIncreasing(uuids));
        assert.isTrue(uuids.every((uuid) => embeddedMs(uuid) === nowMs));
      });

      it("moves on to the next millisecond once the counter runs out", () => {
        const nowMs = Date.now() + 10;
        timers = sinon.useFakeTimers(nowMs);

        // A millisecond holds 2049 to 4096 UUIDs, so this many always reaches the next one and
        // never the one after it.
        const uuids = Array.from({length: 4_097}, () => Utils.uuidv7());

        assert.isTrue(strictlyIncreasing(uuids));
        assert.equal(embeddedMs(uuids[0]), nowMs);
        assert.equal(embeddedMs(uuids.at(-1)), nowMs + 1);
      });

      it("keeps the order when the clock moves back", () => {
        const nowMs = Date.now() + 20;
        timers = sinon.useFakeTimers(nowMs);

        const first = Utils.uuidv7();

        timers.setSystemTime(nowMs - 10);

        const second = Utils.uuidv7();

        assert.isTrue(second > first);
        assert.equal(embeddedMs(second), nowMs);
      });
    });
  });
});
