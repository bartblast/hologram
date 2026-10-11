"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import LiteralSet from "../../assets/js/literal_set.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

describe("LiteralSet", () => {
  const literalSet = (literals) => new LiteralSet(() => literals);

  // <<0xFE>> and <<0xFF>>, neither of which is valid UTF-8
  const nonTextBinary1 = () => Type.bitstring("fe", "hex");
  const nonTextBinary2 = () => Type.bitstring("ff", "hex");

  describe("has()", () => {
    it("builds its literals once, on the first lookup", () => {
      let buildCount = 0;

      const set = new LiteralSet(() => {
        ++buildCount;
        return [Type.atom("a")];
      });

      assert.equal(buildCount, 0);

      set.has(Type.atom("a"));
      set.has(Type.atom("b"));

      assert.equal(buildCount, 1);
    });

    it("does not find a binary given as bytes that is not in the set", () => {
      const set = literalSet([Type.bitstring("abc")]);

      assert.isFalse(set.has(Bitstring.fromBytes([97, 98, 100])));
    });

    it("does not find a binary given as text that is not in the set", () => {
      const set = literalSet([Type.bitstring("abc")]);

      assert.isFalse(set.has(Type.bitstring("abd")));
    });

    it("does not find a binary that is not valid text among binaries that are", () => {
      const set = literalSet([Type.bitstring("abc")]);

      assert.isFalse(set.has(nonTextBinary1()));
    });

    it("does not find a bitstring with leftover bits among binaries", () => {
      const set = literalSet([Type.bitstring("a")]);

      // The 8 bits of "a" followed by 1 more bit
      const term = Type.bitstring([0, 1, 1, 0, 0, 0, 0, 1, 0]);

      assert.isFalse(set.has(term));
    });

    it("does not find a tuple that is not in the set", () => {
      const set = literalSet([Type.tuple([Type.atom("a"), Type.integer(1)])]);

      assert.isFalse(set.has(Type.tuple([Type.atom("a"), Type.integer(2)])));
    });

    it("does not find an atom that is not in the set", () => {
      const set = literalSet([Type.atom("a")]);

      assert.isFalse(set.has(Type.atom("b")));
    });

    it("finds a binary given as bytes", () => {
      const set = literalSet([Type.bitstring("abc")]);

      assert.isTrue(set.has(Bitstring.fromBytes([97, 98, 99])));
    });

    it("finds a binary given as text", () => {
      const set = literalSet([Type.bitstring("abc")]);

      assert.isTrue(set.has(Type.bitstring("abc")));
    });

    it("finds a binary that is not valid text", () => {
      const set = literalSet([nonTextBinary1()]);

      assert.isTrue(set.has(nonTextBinary1()));
    });

    it("finds a bitstring with leftover bits", () => {
      const set = literalSet([Type.bitstring([1, 0, 1])]);

      assert.isTrue(set.has(Type.bitstring([1, 0, 1])));
    });

    it("finds a float", () => {
      const set = literalSet([Type.float(1.5)]);

      assert.isTrue(set.has(Type.float(1.5)));
    });

    it("finds a list", () => {
      const set = literalSet([Type.list([Type.atom("a"), Type.integer(1)])]);

      assert.isTrue(set.has(Type.list([Type.atom("a"), Type.integer(1)])));
    });

    it("finds a tuple", () => {
      const set = literalSet([Type.tuple([Type.atom("a"), Type.integer(1)])]);

      assert.isTrue(set.has(Type.tuple([Type.atom("a"), Type.integer(1)])));
    });

    it("finds an atom", () => {
      const set = literalSet([Type.atom("a")]);

      assert.isTrue(set.has(Type.atom("a")));
    });

    it("finds an integer", () => {
      const set = literalSet([Type.integer(1)]);

      assert.isTrue(set.has(Type.integer(1)));
    });

    it("finds terms of mixed types in one set", () => {
      const set = literalSet([
        Type.atom("a"),
        Type.bitstring("abc"),
        Type.float(1.5),
        Type.integer(1),
        Type.tuple([Type.atom("a"), Type.integer(1)]),
      ]);

      assert.isTrue(set.has(Type.atom("a")));
      assert.isTrue(set.has(Type.bitstring("abc")));
      assert.isTrue(set.has(Type.float(1.5)));
      assert.isTrue(set.has(Type.integer(1)));
      assert.isTrue(set.has(Type.tuple([Type.atom("a"), Type.integer(1)])));
      assert.isFalse(set.has(Type.atom("b")));
    });

    it("keeps the decoded text on a binary given as bytes", () => {
      const set = literalSet([Type.bitstring("abc")]);
      const term = Bitstring.fromBytes([97, 98, 99]);

      set.has(term);

      assert.equal(term.text, "abc");
    });

    it("tells a float from an integer of the same value", () => {
      assert.isFalse(literalSet([Type.integer(1)]).has(Type.float(1.0)));
      assert.isFalse(literalSet([Type.float(1.0)]).has(Type.integer(1)));
    });

    it("tells apart bitstrings that differ only in their bit count", () => {
      // Both are stored as the single byte 0b10100000
      const set = literalSet([Type.bitstring([1, 0, 1])]);

      assert.isFalse(set.has(Type.bitstring([1, 0, 1, 0])));
    });

    it("tells apart two binaries that are not valid text", () => {
      const literal = nonTextBinary1();
      const term = nonTextBinary2();

      // Both now say they are not text, the same way
      Bitstring.isText(literal);
      Bitstring.isText(term);

      assert.isFalse(literalSet([literal]).has(term));
    });
  });
});
