"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexAnalyzer from "../../../assets/js/regex/regex_analyzer.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

const buildGroupMap = (source, opts = {}) =>
  RegexAnalyzer.buildGroupMap(RegexParser.parse(source, opts));

const route = (source, opts = {}) => {
  const ast = RegexParser.parse(source, opts);

  return RegexAnalyzer.route(ast, RegexAnalyzer.buildGroupMap(ast), opts);
};

describe("RegexAnalyzer", () => {
  describe("buildGroupMap()", () => {
    it("returns empty map for pattern without groups", () => {
      assert.deepEqual(buildGroupMap("abc"), {count: 0, names: new Map()});
    });

    it("counts sequential groups", () => {
      assert.deepEqual(buildGroupMap("(a)(b)"), {count: 2, names: new Map()});
    });

    it("counts nested groups", () => {
      assert.deepEqual(buildGroupMap("((a))"), {count: 2, names: new Map()});
    });

    it("counts quantified group", () => {
      assert.deepEqual(buildGroupMap("(a)*"), {count: 1, names: new Map()});
    });

    it("counts group inside lookaround", () => {
      assert.deepEqual(buildGroupMap("(?=(a))"), {count: 1, names: new Map()});
    });

    it("counts group inside option group", () => {
      assert.deepEqual(buildGroupMap("(?i:(a))"), {count: 1, names: new Map()});
    });

    it("counts groups inside conditional incl. assertion condition", () => {
      assert.deepEqual(buildGroupMap("(?(?=(a))(b)|(c))"), {
        count: 3,
        names: new Map(),
      });
    });

    it("counts branch reset group by its widest branch", () => {
      assert.deepEqual(buildGroupMap("(?|(a)(b)|(c))"), {
        count: 2,
        names: new Map(),
      });
    });

    it("maps names to group numbers", () => {
      assert.deepEqual(buildGroupMap("(?<x>a)(?<y>b)"), {
        count: 2,
        names: new Map([
          ["x", [1]],
          ["y", [2]],
        ]),
      });
    });

    it("maps duplicate name to all its numbers with dupnames", () => {
      assert.deepEqual(buildGroupMap("(?<x>a)(?<x>b)", {dupnames: true}), {
        count: 2,
        names: new Map([["x", [1, 2]]]),
      });
    });

    it("deduplicates numbers of names repeated across branch reset branches", () => {
      assert.deepEqual(buildGroupMap("(?|(?<x>a)|(?<x>b))"), {
        count: 1,
        names: new Map([["x", [1]]]),
      });
    });
  });

  describe("route()", () => {
    it("routes plain pattern to native", () => {
      assert.equal(route("^a+[b-z]*(c|d)$"), "native");
    });

    it("routes safe backreference to native", () => {
      assert.equal(route("(a)\\1"), "native");
    });

    it("routes backreference to group with alternation inside to native", () => {
      assert.equal(route("(a|b)\\1"), "native");
    });

    it("routes possessive quantifier and atomic group to native", () => {
      assert.equal(route("a*+(?>b)"), "native");
    });

    it("routes lookarounds to native", () => {
      assert.equal(route("(?=a)(?<!b)"), "native");
    });

    it("routes property escape in unicode mode to native", () => {
      assert.equal(route("\\p{L}", {unicode: true}), "native");
    });

    it("routes property escape with UTF start option to native", () => {
      assert.equal(route("(*UTF)\\p{L}"), "native");
    });

    it("routes inline options to native", () => {
      assert.equal(route("(?i)a(?m:b)"), "native");
    });

    it("routes recursion to interpreted", () => {
      assert.equal(route("a(?R)?"), "interpreted");
    });

    it("routes subroutine call to interpreted", () => {
      assert.equal(route("(a)(?1)"), "interpreted");
    });

    it("routes conditional to interpreted", () => {
      assert.equal(route("(a)(?(1)b|c)"), "interpreted");
    });

    it("routes control verb to interpreted", () => {
      assert.equal(route("a(*SKIP)b"), "interpreted");
    });

    it("routes match start reset to interpreted", () => {
      assert.equal(route("a\\Kb"), "interpreted");
    });

    it("routes \\G anchor to interpreted", () => {
      assert.equal(route("\\Ga"), "interpreted");
    });

    it("routes script run to interpreted", () => {
      assert.equal(route("(*sr:ab)"), "interpreted");
    });

    it("routes branch reset group to interpreted", () => {
      assert.equal(route("(?|(a)|(b))"), "interpreted");
    });

    it("routes non-atomic lookaround to interpreted", () => {
      assert.equal(route("(?*a)"), "interpreted");
    });

    it("routes grapheme cluster to interpreted", () => {
      assert.equal(route("\\X"), "interpreted");
    });

    it("routes single byte escape to interpreted", () => {
      assert.equal(route("\\C"), "interpreted");
    });

    it("routes property escape in 8-bit mode to interpreted", () => {
      assert.equal(route("\\p{L}"), "interpreted");
    });

    it("routes class with property escape in 8-bit mode to interpreted", () => {
      assert.equal(route("[\\p{L}]"), "interpreted");
    });

    it("routes match limit start option to interpreted", () => {
      assert.equal(route("(*LIMIT_MATCH=100)a"), "interpreted");
    });

    it("routes duplicate names to interpreted", () => {
      assert.equal(route("(?<x>a)(?<x>b)", {dupnames: true}), "interpreted");
    });

    it("routes backreference to optional group to interpreted", () => {
      assert.equal(route("(a)?\\1"), "interpreted");
    });

    it("routes forward reference to interpreted", () => {
      assert.equal(route("\\2(a)(b)"), "interpreted");
    });

    it("routes backreference to group in one alternation branch to interpreted", () => {
      assert.equal(route("((a)|b)\\2"), "interpreted");
    });
  });
});
