"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../../support/helpers.mjs";

import RegexAnalyzer, {
  resolveGroupNumbers,
  walkAst,
} from "../../../../assets/js/erts/regex/regex_analyzer.mjs";

import RegexParser from "../../../../assets/js/erts/regex/regex_parser.mjs";

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

  describe("resolveGroupNumbers()", () => {
    const names = new Map([
      ["x", [1]],
      ["y", [2, 3]],
    ]);

    it("resolves a reference by number", () => {
      assert.deepEqual(
        resolveGroupNumbers({number: 2, name: null}, names),
        [2],
      );
    });

    it("resolves a reference by name", () => {
      assert.deepEqual(
        resolveGroupNumbers({number: null, name: "x"}, names),
        [1],
      );
    });

    it("resolves a duplicate name to all its numbers", () => {
      assert.deepEqual(
        resolveGroupNumbers({number: null, name: "y"}, names),
        [2, 3],
      );
    });

    it("resolves an unknown name to no numbers", () => {
      assert.deepEqual(
        resolveGroupNumbers({number: null, name: "z"}, names),
        [],
      );
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

    it("routes option setting leaking across alternation branches to interpreted", () => {
      assert.equal(route("a(?i)b|c"), "interpreted");
    });

    it("routes group-enclosed option setting in alternation to native", () => {
      assert.equal(route("(?:a(?i)b)|c"), "native");
    });

    it("routes ucp option to interpreted", () => {
      assert.equal(route("a", {ucp: true}), "interpreted");
    });

    it("routes UCP start option to interpreted", () => {
      assert.equal(route("(*UCP)a"), "interpreted");
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

  describe("walkAst()", () => {
    const visitedTypes = (source) => {
      const types = [];

      walkAst(RegexParser.parse(source), (node) => types.push(node.type));

      return types;
    };

    it("visits a leaf pattern", () => {
      assert.deepEqual(visitedTypes("a"), ["literal"]);
    });

    it("visits alternation branches in order", () => {
      assert.deepEqual(visitedTypes("a|b"), [
        "alternation",
        "literal",
        "literal",
      ]);
    });

    it("visits atomic group content", () => {
      assert.deepEqual(visitedTypes("(?>a)"), ["atomicGroup", "literal"]);
    });

    it("visits branch reset group content", () => {
      assert.deepEqual(visitedTypes("(?|(a))"), [
        "branchResetGroup",
        "group",
        "literal",
      ]);
    });

    it("visits concatenation items in order", () => {
      assert.deepEqual(visitedTypes("ab"), [
        "concatenation",
        "literal",
        "literal",
      ]);
    });

    it("visits conditional assertion condition, yes and no branches", () => {
      assert.deepEqual(visitedTypes("(?(?=x)a|b)"), [
        "conditional",
        "lookaround",
        "literal",
        "literal",
        "literal",
      ]);
    });

    it("visits conditional group condition branches only", () => {
      assert.deepEqual(visitedTypes("(x)(?(1)a|b)"), [
        "concatenation",
        "group",
        "literal",
        "conditional",
        "literal",
        "literal",
      ]);
    });

    it("visits conditional without no branch", () => {
      assert.deepEqual(visitedTypes("(?(?=x)a)"), [
        "conditional",
        "lookaround",
        "literal",
        "literal",
      ]);
    });

    it("visits group content after the group itself", () => {
      assert.deepEqual(visitedTypes("(ab)"), [
        "group",
        "concatenation",
        "literal",
        "literal",
      ]);
    });

    it("visits lookaround content", () => {
      assert.deepEqual(visitedTypes("(?=a)"), ["lookaround", "literal"]);
    });

    it("visits non-capturing group content", () => {
      assert.deepEqual(visitedTypes("(?:a)"), ["nonCapturingGroup", "literal"]);
    });

    it("visits option group content", () => {
      assert.deepEqual(visitedTypes("(?i:a)"), ["optionGroup", "literal"]);
    });

    it("visits quantifier item", () => {
      assert.deepEqual(visitedTypes("a+"), ["quantifier", "literal"]);
    });

    it("visits script run content", () => {
      assert.deepEqual(visitedTypes("(*script_run:a)"), [
        "scriptRun",
        "literal",
      ]);
    });
  });
});
