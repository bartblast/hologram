"use strict";

import {
  assert,
  assertBoxedFalse,
  assertBoxedTrue,
  assertFrozen,
  cleanup,
} from "../support/commons";
beforeEach(() => cleanup());

import Keyword from "../../../assets/js/hologram/elixir/keyword";
import Type from "../../../assets/js/hologram/type";

describe("has_key$question()", () => {
  let keywords;

  beforeEach(() => {
    keywords = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);
  });

  it("returns boxed true if the keyword list has the key", () => {
    const key = Type.atom("b");
    const result = Keyword.has_key$question(keywords, key);

    assertBoxedTrue(result);
  });

  it("returns boxed false if the keyword list doesn't have the key", () => {
    const key = Type.atom("c");
    const result = Keyword.has_key$question(keywords, key);

    assertBoxedFalse(result);
  });
});

describe("put()", () => {
  it("inserts the given key-value pair at the beginning of the keyword list", () => {
    const keywords = Type.list([Type.tuple([Type.atom("a"), Type.integer(1)])]);

    const result = Keyword.put(keywords, Type.atom("b"), Type.integer(2));

    const expected = Type.list([
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.tuple([Type.atom("a"), Type.integer(1)]),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("removes the previous matching entry when the keyword list already has a single entry with the given key", () => {
    const keywords = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);

    const result = Keyword.put(keywords, Type.atom("a"), Type.integer(3));

    const expected = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(3)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("removes the previous matching entries when the keyword list already has multiple entries with the given key", () => {
    const keywords = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(1)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
      Type.tuple([Type.atom("a"), Type.integer(4)]),
    ]);

    const result = Keyword.put(keywords, Type.atom("a"), Type.integer(3));

    const expected = Type.list([
      Type.tuple([Type.atom("a"), Type.integer(3)]),
      Type.tuple([Type.atom("b"), Type.integer(2)]),
    ]);

    assert.deepStrictEqual(result, expected);
  });

  it("returns frozen object", () => {
    const result = Keyword.put(Type.list(), Type.atom("a"), Type.integer(1));
    assertFrozen(result);
  });
});
