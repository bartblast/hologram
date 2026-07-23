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
});
