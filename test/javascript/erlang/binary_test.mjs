"use strict";

import {
  assert,
  assertBoxedError,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import Bitstring from "../../../assets/js/bitstring.mjs";
import Erlang_Binary from "../../../assets/js/erlang/binary.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test

describe("Erlang_Binary", () => {
  describe("compile_pattern/1", () => {
    it("creates a Boyer-Moore pattern for a single binary", () => {
      const pattern = Bitstring.fromText("test");
      const compiled = Erlang_Binary["compile_pattern/1"](pattern);

      assert.equal(compiled.type, "tuple");
      assert.equal(compiled.data[0].value, "bm");
      assert.equal(compiled.data[1].algorithm, "boyer_moore");
    });

    it("creates an Aho-Corasick pattern for a list of binaries", () => {
      const patterns = Type.list([
        Bitstring.fromText("foo"),
        Bitstring.fromText("bar"),
      ]);
      const compiled = Erlang_Binary["compile_pattern/1"](patterns);

      assert.equal(compiled.type, "tuple");
      assert.equal(compiled.data[0].value, "ac");
      assert.equal(compiled.data[1].algorithm, "aho_corasick");
    });

    it("raises error for invalid pattern type", () => {
      assertBoxedError(
        () => Erlang_Binary["compile_pattern/1"](Type.integer(42)),
        "ArgumentError",
        "pattern must be a binary or a list of binaries",
      );
    });

    it("raises error for empty pattern list", () => {
      const patterns = Type.list([]);
      assertBoxedError(
        () => Erlang_Binary["compile_pattern/1"](patterns),
        "ArgumentError",
        "pattern list must not be empty",
      );
    });
  });

  describe("match/2 and match/3", () => {
    describe("with single pattern (Boyer-Moore)", () => {
      it("finds first match", () => {
        const pattern = Bitstring.fromText("lo");
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["match/2"](subject, pattern);

        assert.equal(result.type, "tuple");
        assert.equal(result.data[0].value, 3n); // Position
        assert.equal(result.data[1].value, 2n); // Length
      });

      it("respects scope option", () => {
        const pattern = Bitstring.fromText("lo");
        const subject = Bitstring.fromText("hello world");
        // scope: {0, 5} means only search in "hello"
        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([Type.integer(0), Type.integer(5)])])
        ]);
        const result = Erlang_Binary["match/3"](subject, pattern, options);

        // Should find "lo" at position 3 in "hello"
        assert.equal(result.type, "tuple");
        assert.equal(result.data[0].value, 3n);
        assert.equal(result.data[1].value, 2n);
      });

      it("returns nomatch when pattern outside scope", () => {
        const pattern = Bitstring.fromText("world");
        const subject = Bitstring.fromText("hello world");
        // scope: {0, 5} means only search in "hello"
        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([Type.integer(0), Type.integer(5)])])
        ]);
        const result = Erlang_Binary["match/3"](subject, pattern, options);

        assert.equal(result.type, "atom");
        assert.equal(result.value, "nomatch");
      });

      it("returns nomatch when pattern not found", () => {
        const pattern = Bitstring.fromText("xyz");
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["match/2"](subject, pattern);

        assert.equal(result.type, "atom");
        assert.equal(result.value, "nomatch");
      });

      it("finds match at beginning", () => {
        const pattern = Bitstring.fromText("hel");
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["match/2"](subject, pattern);

        assert.equal(result.data[0].value, 0n);
        assert.equal(result.data[1].value, 3n);
      });

      it("finds match at end", () => {
        const pattern = Bitstring.fromText("rld");
        const subject = Bitstring.fromText("hello world");
        const result = Erlang_Binary["match/2"](subject, pattern);

        assert.equal(result.data[0].value, 8n);
        assert.equal(result.data[1].value, 3n);
      });
    });

    describe("with multiple patterns (Aho-Corasick)", () => {
      it("finds first match among multiple patterns", () => {
        const patterns = Type.list([
          Bitstring.fromText("world"),
          Bitstring.fromText("hello"),
        ]);
        const subject = Bitstring.fromText("hello world");
        const result = Erlang_Binary["match/2"](subject, patterns);

        assert.equal(result.type, "tuple");
        assert.equal(result.data[0].value, 0n); // "hello" comes first
        assert.equal(result.data[1].value, 5n);
      });

      it("returns nomatch when no patterns found", () => {
        const patterns = Type.list([
          Bitstring.fromText("foo"),
          Bitstring.fromText("bar"),
        ]);
        const subject = Bitstring.fromText("hello world");
        const result = Erlang_Binary["match/2"](subject, patterns);

        assert.equal(result.type, "atom");
        assert.equal(result.value, "nomatch");
      });
    });

    describe("with compiled pattern", () => {
      it("works with compiled Boyer-Moore pattern", () => {
        const pattern = Bitstring.fromText("lo");
        const compiled = Erlang_Binary["compile_pattern/1"](pattern);
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["match/2"](subject, compiled);

        assert.equal(result.type, "tuple");
        assert.equal(result.data[0].value, 3n);
        assert.equal(result.data[1].value, 2n);
      });
    });
  });

  describe("matches/2 and matches/3", () => {
    describe("with single pattern", () => {
      it("finds all non-overlapping matches", () => {
        const pattern = Bitstring.fromText("ab");
        const subject = Bitstring.fromText("ababab");
        const result = Erlang_Binary["matches/2"](subject, pattern);

        assert.equal(result.type, "list");
        assert.equal(result.data.length, 3);

        assert.equal(result.data[0].data[0].value, 0n);
        assert.equal(result.data[0].data[1].value, 2n);

        assert.equal(result.data[1].data[0].value, 2n);
        assert.equal(result.data[1].data[1].value, 2n);

        assert.equal(result.data[2].data[0].value, 4n);
        assert.equal(result.data[2].data[1].value, 2n);
      });

      it("respects scope option", () => {
        const pattern = Bitstring.fromText("ab");
        const subject = Bitstring.fromText("ababab");
        // scope: {2, 4} means start at byte 2, length 4 (covering "abab")
        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([Type.integer(2), Type.integer(4)])])
        ]);
        const result = Erlang_Binary["matches/3"](subject, pattern, options);

        // Should only find matches within the scope at positions 2 and 4
        assert.equal(result.data.length, 2);
        assert.equal(result.data[0].data[0].value, 2n);
        assert.equal(result.data[0].data[1].value, 2n);
        assert.equal(result.data[1].data[0].value, 4n);
        assert.equal(result.data[1].data[1].value, 2n);
      });

      it("returns empty list when no matches", () => {
        const pattern = Bitstring.fromText("xyz");
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["matches/2"](subject, pattern);

        assert.equal(result.type, "list");
        assert.equal(result.data.length, 0);
      });

      it("handles single match", () => {
        const pattern = Bitstring.fromText("world");
        const subject = Bitstring.fromText("hello world");
        const result = Erlang_Binary["matches/2"](subject, pattern);

        assert.equal(result.data.length, 1);
        assert.equal(result.data[0].data[0].value, 6n);
        assert.equal(result.data[0].data[1].value, 5n);
      });
    });

    describe("with multiple patterns", () => {
      it("finds all non-overlapping matches", () => {
        const patterns = Type.list([
          Bitstring.fromText("foo"),
          Bitstring.fromText("bar"),
        ]);
        const subject = Bitstring.fromText("foo and bar");
        const result = Erlang_Binary["matches/2"](subject, patterns);

        assert.equal(result.type, "list");
        assert.equal(result.data.length, 2);

        assert.equal(result.data[0].data[0].value, 0n); // foo
        assert.equal(result.data[0].data[1].value, 3n);

        assert.equal(result.data[1].data[0].value, 8n); // bar
        assert.equal(result.data[1].data[1].value, 3n);
      });

      it("handles overlapping patterns correctly", () => {
        const patterns = Type.list([
          Bitstring.fromText("abc"),
          Bitstring.fromText("bcd"),
        ]);
        const subject = Bitstring.fromText("abcd");
        const result = Erlang_Binary["matches/2"](subject, patterns);

        // Should only return "abc" since it comes first
        assert.equal(result.data.length, 1);
        assert.equal(result.data[0].data[0].value, 0n);
        assert.equal(result.data[0].data[1].value, 3n);
      });
    });
  });

  describe("split/2 and split/3", () => {
    describe("examples from Erlang documentation", () => {
      it('binary:split(<<"the quick brown fox">>, <<" ">>, [])', () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("the quick brown fox");
        const result = Erlang_Binary["split/2"](subject, pattern);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "the");
        assert.equal(Bitstring.toText(result.data[1]), "quick brown fox");
      });

      it('binary:split(<<"the quick brown fox">>, <<" ">>, [global])', () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("the quick brown fox");
        const options = Type.list([Type.atom("global")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        assert.equal(result.data.length, 4);
        assert.equal(Bitstring.toText(result.data[0]), "the");
        assert.equal(Bitstring.toText(result.data[1]), "quick");
        assert.equal(Bitstring.toText(result.data[2]), "brown");
        assert.equal(Bitstring.toText(result.data[3]), "fox");
      });

      it("binary:split(<<1,255,4,0,0,0,2,3>>, [<<0,0,0>>,<<2>>], [])", () => {
        const patterns = Type.list([
          Bitstring.fromBytes(new Uint8Array([0, 0, 0])),
          Bitstring.fromBytes(new Uint8Array([2]))
        ]);
        const subject = Bitstring.fromBytes(new Uint8Array([1, 255, 4, 0, 0, 0, 2, 3]));
        const result = Erlang_Binary["split/2"](subject, patterns);

        assert.equal(result.data.length, 2);
        assert.deepEqual(result.data[0].bytes, new Uint8Array([1, 255, 4]));
        assert.deepEqual(result.data[1].bytes, new Uint8Array([2, 3]));
      });

      it("binary:split(<<0,1,0,0,4,255,255,9>>, [<<0,0>>, <<255,255>>], [global])", () => {
        const patterns = Type.list([
          Bitstring.fromBytes(new Uint8Array([0, 0])),
          Bitstring.fromBytes(new Uint8Array([255, 255]))
        ]);
        const subject = Bitstring.fromBytes(new Uint8Array([0, 1, 0, 0, 4, 255, 255, 9]));
        const options = Type.list([Type.atom("global")]);
        const result = Erlang_Binary["split/3"](subject, patterns, options);

        assert.equal(result.data.length, 3);
        assert.deepEqual(result.data[0].bytes, new Uint8Array([0, 1]));
        assert.deepEqual(result.data[1].bytes, new Uint8Array([4]));
        assert.deepEqual(result.data[2].bytes, new Uint8Array([9]));
      });

      it('binary:split(<<"banana">>, [<<"a">>], [{scope,{2,3}}])', () => {
        const pattern = Bitstring.fromText("a");
        const subject = Bitstring.fromText("banana");
        const options = Type.list([
          Type.tuple([Type.atom("scope"), Type.tuple([Type.integer(2), Type.integer(3)])])
        ]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "ban");
        assert.equal(Bitstring.toText(result.data[1]), "na");
      });
    });

    describe("with single pattern", () => {
      it("splits on first match by default", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello world again");
        const result = Erlang_Binary["split/2"](subject, pattern);

        assert.equal(result.type, "list");
        assert.equal(result.data.length, 2);

        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), "world again");
      });

      it("splits on all matches with global option", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello world again");
        const options = Type.list([Type.atom("global")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        assert.equal(result.data.length, 3);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), "world");
        assert.equal(Bitstring.toText(result.data[2]), "again");
      });

      it("returns original binary when no match found", () => {
        const pattern = Bitstring.fromText("xyz");
        const subject = Bitstring.fromText("hello");
        const result = Erlang_Binary["split/2"](subject, pattern);

        assert.equal(result.data.length, 1);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
      });

      it("handles consecutive delimiters", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello  world");
        const options = Type.list([Type.atom("global")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        assert.equal(result.data.length, 3);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), ""); // Empty part
        assert.equal(Bitstring.toText(result.data[2]), "world");
      });

      it("handles delimiter at start", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText(" hello");
        const result = Erlang_Binary["split/2"](subject, pattern);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), ""); // Empty part
        assert.equal(Bitstring.toText(result.data[1]), "hello");
      });

      it("handles delimiter at end", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello ");
        const result = Erlang_Binary["split/2"](subject, pattern);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), ""); // Empty part
      });

      it("removes trailing empty parts with trim option", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello ");
        const options = Type.list([Type.atom("trim")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        // Should only have "hello", trailing empty part is removed
        assert.equal(result.data.length, 1);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
      });

      it("removes trailing empty parts with trim and global options", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText("hello  world  ");
        const options = Type.list([Type.atom("global"), Type.atom("trim")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        // Should remove trailing empty parts but keep middle ones
        assert.equal(result.data.length, 3);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), "");
        assert.equal(Bitstring.toText(result.data[2]), "world");
      });

      it("removes all empty parts with trim_all option", () => {
        const pattern = Bitstring.fromText(" ");
        const subject = Bitstring.fromText(" hello  world ");
        const options = Type.list([Type.atom("global"), Type.atom("trim_all")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        // Should only have non-empty parts
        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), "world");
      });

      it("trim_all removes leading, trailing, and middle empty parts", () => {
        const pattern = Bitstring.fromText(",");
        const subject = Bitstring.fromText(",a,,b,");
        const options = Type.list([Type.atom("global"), Type.atom("trim_all")]);
        const result = Erlang_Binary["split/3"](subject, pattern, options);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "a");
        assert.equal(Bitstring.toText(result.data[1]), "b");
      });
    });

    describe("with multiple patterns", () => {
      it("splits on first match of any pattern", () => {
        const patterns = Type.list([
          Bitstring.fromText(","),
          Bitstring.fromText(";"),
        ]);
        const subject = Bitstring.fromText("a,b;c");
        const result = Erlang_Binary["split/2"](subject, patterns);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "a");
        assert.equal(Bitstring.toText(result.data[1]), "b;c");
      });

      it("splits on all matches with global option", () => {
        const patterns = Type.list([
          Bitstring.fromText(","),
          Bitstring.fromText(";"),
        ]);
        const subject = Bitstring.fromText("a,b;c");
        const options = Type.list([Type.atom("global")]);
        const result = Erlang_Binary["split/3"](subject, patterns, options);

        assert.equal(result.data.length, 3);
        assert.equal(Bitstring.toText(result.data[0]), "a");
        assert.equal(Bitstring.toText(result.data[1]), "b");
        assert.equal(Bitstring.toText(result.data[2]), "c");
      });
    });

    describe("with compiled pattern", () => {
      it("works with compiled pattern", () => {
        const pattern = Bitstring.fromText(" ");
        const compiled = Erlang_Binary["compile_pattern/1"](pattern);
        const subject = Bitstring.fromText("hello world");
        const result = Erlang_Binary["split/2"](subject, compiled);

        assert.equal(result.data.length, 2);
        assert.equal(Bitstring.toText(result.data[0]), "hello");
        assert.equal(Bitstring.toText(result.data[1]), "world");
      });
    });
  });
});

