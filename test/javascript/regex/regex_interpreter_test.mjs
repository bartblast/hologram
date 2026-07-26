"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
} from "../support/helpers.mjs";

import RegexInterpreter from "../../../assets/js/regex/regex_interpreter.mjs";
import RegexParser from "../../../assets/js/regex/regex_parser.mjs";

defineGlobalErlangAndElixirModules();

const match = (source, subject, opts = {}) => {
  const result = matchFull(source, subject, opts);

  return result === null ? null : {start: result.start, end: result.end};
};

const matchFull = (source, subject, opts = {}) =>
  RegexInterpreter.match(RegexParser.parse(source, opts), subject, opts);

describe("RegexInterpreter", () => {
  describe("match()", () => {
    describe("alternation", () => {
      it("matches the first branch that succeeds", () => {
        assert.deepEqual(match("x|bc", "abcd"), {start: 1, end: 3});
      });

      it("prefers earlier branches at the same position", () => {
        assert.deepEqual(match("a|ab", "ab"), {start: 0, end: 1});
      });

      it("backtracks into later branches", () => {
        assert.deepEqual(match("ab|ac", "ac"), {start: 0, end: 2});
      });
    });

    describe("anchors", () => {
      it("anchors ^ to the subject start by default", () => {
        assert.isNull(match("^b", "ab"));
      });

      it("anchors \\A to the subject start even when scanning", () => {
        assert.isNull(match("\\Ab", "ab"));
      });

      it("anchors \\z to the subject end", () => {
        assert.isNull(match("a\\z", "ab"));
      });

      it("matches \\Z before a final newline", () => {
        assert.deepEqual(match("a\\Z", "a\n"), {start: 0, end: 1});
      });

      it("matches default $ before a final newline", () => {
        assert.deepEqual(match("a$", "a\n"), {start: 0, end: 1});
      });

      it("anchors $ to the subject end with dollar_endonly", () => {
        assert.isNull(match("a$", "a\n", {dollarEndonly: true}));
      });

      it("matches multiline ^ after a newline", () => {
        assert.deepEqual(match("^b", "a\nb", {multiline: true}), {
          start: 2,
          end: 3,
        });
      });

      it("matches multiline $ before a newline", () => {
        assert.deepEqual(match("a$", "a\nb", {multiline: true}), {
          start: 0,
          end: 1,
        });
      });

      it("matches word boundary", () => {
        assert.deepEqual(match("\\bb", "a b"), {start: 2, end: 3});
      });

      it("matches non-word boundary", () => {
        assert.deepEqual(match("\\Bb", "ab"), {start: 1, end: 2});
      });

      it("anchors \\G to the start offset", () => {
        assert.isNull(match("\\Gb", "ab"));
      });

      it("matches \\G at a non-zero start offset", () => {
        assert.deepEqual(match("\\Gb", "ab", {startPosition: 1}), {
          start: 1,
          end: 2,
        });
      });
    });

    describe("atomic matching", () => {
      it("does not backtrack into atomic group", () => {
        assert.isNull(match("(?>a+)a", "aaa"));
      });

      it("matches atomic group and continues", () => {
        assert.deepEqual(match("(?>a+)b", "aab"), {start: 0, end: 3});
      });

      it("rolls back captures locked inside a failed atomic group", () => {
        assert.deepEqual(matchFull("(?>(a))x|([a-z])y", "ay"), {
          start: 0,
          end: 2,
          captures: [null, null, {start: 0, end: 1}],
        });
      });

      it("does not give back possessive repetitions", () => {
        assert.isNull(match("a*+a", "aaa"));
      });

      it("matches possessive quantifier and continues", () => {
        assert.deepEqual(match("a*+b", "aab"), {start: 0, end: 3});
      });
    });

    describe("backreferences", () => {
      it("matches captured text", () => {
        assert.deepEqual(match("(a)\\1", "aa"), {start: 0, end: 2});
      });

      it("fails when captured text differs", () => {
        assert.isNull(match("(ab)\\1", "abac"));
      });

      it("fails on reference to non-participating group", () => {
        assert.isNull(match("(a)?\\1", "b"));
      });

      it("matches reference to participating optional group", () => {
        assert.deepEqual(match("(a)?\\1", "aa"), {start: 0, end: 2});
      });

      it("matches captured text caselessly", () => {
        assert.deepEqual(match("(a)\\1", "aA", {caseless: true}), {
          start: 0,
          end: 2,
        });
      });

      it("matches named reference", () => {
        assert.deepEqual(match("(?<x>a)\\k<x>", "aa"), {start: 0, end: 2});
      });

      it("uses the first participating group for duplicate names", () => {
        assert.deepEqual(
          match("(?<x>a)(?<x>b)\\k<x>", "aba", {dupnames: true}),
          {start: 0, end: 3},
        );
      });

      it("sees captures from earlier quantifier iterations", () => {
        assert.deepEqual(match("^(a|b\\1)+$", "aba"), {start: 0, end: 3});
      });

      it("fails through an atomic lookahead capture", () => {
        assert.isNull(match("(?=(a|ab))\\1x", "abx"));
      });

      it("retries a non-atomic lookahead capture", () => {
        assert.deepEqual(match("(?*(a|ab))\\1x", "abx"), {start: 0, end: 3});
      });
    });

    describe("captures", () => {
      it("captures sequential groups", () => {
        assert.deepEqual(matchFull("(a)(b)", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 0, end: 1}, {start: 1, end: 2}],
        });
      });

      it("captures nested groups", () => {
        assert.deepEqual(matchFull("((a)b)", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 0, end: 2}, {start: 0, end: 1}],
        });
      });

      it("leaves non-participating group unset", () => {
        assert.deepEqual(matchFull("(a)|(b)", "b"), {
          start: 0,
          end: 1,
          captures: [null, null, {start: 0, end: 1}],
        });
      });

      it("leaves skipped optional group unset", () => {
        assert.deepEqual(matchFull("(a)?b", "b"), {
          start: 0,
          end: 1,
          captures: [null, null],
        });
      });

      it("keeps the last iteration of a quantified group", () => {
        assert.deepEqual(matchFull("([ab])+", "ab"), {
          start: 0,
          end: 2,
          captures: [null, {start: 1, end: 2}],
        });
      });

      it("restores captures abandoned by backtracking", () => {
        assert.deepEqual(matchFull("(a)b|ac", "ac"), {
          start: 0,
          end: 2,
          captures: [null, null],
        });
      });
    });

    describe("classes", () => {
      it("matches char in range", () => {
        assert.deepEqual(match("[b-d]", "ad"), {start: 1, end: 2});
      });

      it("matches char in negated class", () => {
        assert.deepEqual(match("[^a]", "aab"), {start: 2, end: 3});
      });

      it("returns null when no char is in class", () => {
        assert.isNull(match("[x-z]", "abc"));
      });

      it("matches caseless range members", () => {
        assert.deepEqual(match("[A-Z]", "x", {caseless: true}), {
          start: 0,
          end: 1,
        });
      });

      it("matches shorthand member", () => {
        assert.deepEqual(match("[\\d-]", "-"), {start: 0, end: 1});
      });

      it("matches negated shorthand member", () => {
        assert.deepEqual(match("[\\W]", "a!"), {start: 1, end: 2});
      });

      it("matches POSIX class member", () => {
        assert.deepEqual(match("[[:digit:]]", "a5"), {start: 1, end: 2});
      });

      it("matches negated POSIX class member", () => {
        assert.deepEqual(match("[[:^alpha:]]", "ab1"), {start: 2, end: 3});
      });

      it("matches Unicode property member", () => {
        assert.deepEqual(match("[\\p{L}5]", "!5"), {start: 1, end: 2});
      });
    });

    describe("conditionals", () => {
      it("takes the yes branch when the group participated", () => {
        assert.deepEqual(match("(a)?(?(1)b|c)", "ab"), {start: 0, end: 2});
      });

      it("takes the no branch when the group didn't participate", () => {
        assert.deepEqual(match("(a)?(?(1)b|c)", "c"), {start: 0, end: 1});
      });

      it("matches empty without a no branch", () => {
        assert.deepEqual(match("(a)?(?(1)b)", "x"), {start: 0, end: 0});
      });

      it("evaluates named group condition", () => {
        assert.deepEqual(match("(?<x>a)?(?(<x>)b|c)", "ab"), {
          start: 0,
          end: 2,
        });
      });

      it("evaluates whole-pattern recursion condition", () => {
        assert.deepEqual(match("(?(R)a|b(?R))", "ba"), {start: 0, end: 2});
      });

      it("evaluates numbered recursion condition", () => {
        assert.deepEqual(match("^(a(?(R1)b|c))(?1)$", "acab"), {
          start: 0,
          end: 4,
        });
      });

      it("never takes the DEFINE branch directly", () => {
        assert.deepEqual(match("(?(DEFINE)(?<x>a))(?&x)", "a"), {
          start: 0,
          end: 1,
        });
      });

      it("evaluates assertion condition", () => {
        assert.deepEqual(match("(?(?=a)ab|cd)", "ab"), {start: 0, end: 2});
      });

      it("takes the no branch when the assertion fails", () => {
        assert.deepEqual(match("(?(?=a)ab|cd)", "cd"), {start: 0, end: 2});
      });

      it("evaluates version condition", () => {
        assert.deepEqual(match("(?(VERSION>=10)a|b)", "a"), {start: 0, end: 1});
      });

      it("fails version condition beyond the emulated version", () => {
        assert.deepEqual(match("(?(VERSION>=99)a|b)", "b"), {start: 0, end: 1});
      });
    });

    describe("escape sets", () => {
      it("matches digits with \\d", () => {
        assert.deepEqual(match("\\d+", "ab12"), {start: 2, end: 4});
      });

      it("matches non-digits with \\D", () => {
        assert.deepEqual(match("\\D", "12a"), {start: 2, end: 3});
      });

      it("excludes NBSP from \\s", () => {
        assert.isNull(match("\\s", "\u00a0"));
      });

      it("matches vertical tab with \\s", () => {
        assert.deepEqual(match("\\s", "\x0b"), {start: 0, end: 1});
      });

      it("matches NBSP with \\h", () => {
        assert.deepEqual(match("\\h", "\u00a0"), {start: 0, end: 1});
      });

      it("matches NEL with \\v", () => {
        assert.deepEqual(match("\\v", "\x85"), {start: 0, end: 1});
      });

      it("matches word chars with \\w", () => {
        assert.deepEqual(match("\\w+", "!a_1"), {start: 1, end: 4});
      });

      it("matches letter with \\p{L}", () => {
        assert.deepEqual(match("\\p{L}", "1é"), {start: 1, end: 2});
      });

      it("rejects lowercase letter with \\p{Lu}", () => {
        assert.isNull(match("\\p{Lu}", "a"));
      });

      it("matches non-letter with \\P{L}", () => {
        assert.deepEqual(match("\\P{L}", "a1"), {start: 1, end: 2});
      });

      it("matches script property", () => {
        assert.deepEqual(match("\\p{Greek}", "aα", {unicode: true}), {
          start: 1,
          end: 2,
        });
      });

      it("matches name=value property", () => {
        assert.deepEqual(match("\\p{sc=Greek}", "aα", {unicode: true}), {
          start: 1,
          end: 2,
        });
      });

      it("matches anything with \\p{Any}", () => {
        assert.deepEqual(match("\\p{Any}", "\n"), {start: 0, end: 1});
      });

      it("excludes underscore from \\p{Xan}", () => {
        assert.isNull(match("\\p{Xan}", "_"));
      });

      it("includes underscore in \\p{Xwd}", () => {
        assert.deepEqual(match("\\p{Xwd}", "_"), {start: 0, end: 1});
      });
    });

    describe("lookarounds", () => {
      it("matches positive lookahead without consuming", () => {
        assert.deepEqual(match("a(?=b)", "ab"), {start: 0, end: 1});
      });

      it("keeps captures from positive lookahead", () => {
        assert.deepEqual(matchFull("a(?=(b))", "ab"), {
          start: 0,
          end: 1,
          captures: [null, {start: 1, end: 2}],
        });
      });

      it("matches negative lookahead", () => {
        assert.deepEqual(match("a(?!b)", "ac"), {start: 0, end: 1});
      });

      it("fails negative lookahead when content matches", () => {
        assert.isNull(match("a(?!b)", "ab"));
      });

      it("retains no captures from negative lookahead", () => {
        assert.deepEqual(matchFull("a(?!(x))", "ab"), {
          start: 0,
          end: 1,
          captures: [null, null],
        });
      });

      it("matches positive lookbehind", () => {
        assert.deepEqual(match("(?<=a)b", "ab"), {start: 1, end: 2});
      });

      it("fails positive lookbehind without preceding content", () => {
        assert.isNull(match("(?<=x)b", "ab"));
      });

      it("matches variable-length lookbehind", () => {
        assert.deepEqual(match("(?<=a{1,3})b", "aaab"), {start: 3, end: 4});
      });

      it("matches negative lookbehind", () => {
        assert.deepEqual(match("(?<!a)b", "cb"), {start: 1, end: 2});
      });

      it("fails negative lookbehind when content precedes", () => {
        assert.isNull(match("(?<!a)b", "ab"));
      });

      it("matches negative lookbehind at the subject start", () => {
        assert.deepEqual(match("(?<!a)b", "b"), {start: 0, end: 1});
      });

      it("matches lookahead nested inside lookbehind", () => {
        assert.deepEqual(match("(?<=(?=ab)a)b", "ab"), {start: 1, end: 2});
      });

      it("matches non-atomic lookahead", () => {
        assert.deepEqual(match("(?*a)a", "a"), {start: 0, end: 1});
      });

      it("matches alpha assertion lookaround", () => {
        assert.deepEqual(match("a(*pla:b)", "ab"), {start: 0, end: 1});
      });
    });

    describe("match start reset", () => {
      it("resets the reported match start with \\K", () => {
        assert.deepEqual(match("a\\Kb", "ab"), {start: 1, end: 2});
      });

      it("discards \\K from an abandoned branch", () => {
        assert.deepEqual(match("a\\Kx|ab", "ab"), {start: 0, end: 2});
      });
    });

    describe("match limits", () => {
      it("matches within the default limits", () => {
        assert.deepEqual(match("a+b", "aaab"), {start: 0, end: 4});
      });

      it("reports no match when match_limit is exceeded", () => {
        assert.isNull(match("a+b", "aaab", {matchLimit: 3}));
      });

      it("reports no match when match_limit_recursion is exceeded", () => {
        assert.isNull(match("a+b", "aaab", {matchLimitRecursion: 2}));
      });

      it("caps the limit with the LIMIT_MATCH start verb", () => {
        assert.isNull(match("(*LIMIT_MATCH=3)a+b", "aaab"));
      });

      it("reports no match on runaway recursion", () => {
        assert.isNull(match("(?R)", "a"));
      });
    });

    describe("newline handling", () => {
      it("excludes the newline from dot", () => {
        assert.isNull(match(".", "\n"));
      });

      it("matches newline with dot in dotall mode", () => {
        assert.deepEqual(match(".", "\n", {dotall: true}), {start: 0, end: 1});
      });

      it("matches CR with dot under the crlf convention", () => {
        assert.deepEqual(match(".", "\r", {newline: "crlf"}), {
          start: 0,
          end: 1,
        });
      });

      it("excludes the convention newline from \\N regardless of dotall", () => {
        assert.isNull(match("\\N", "\n", {dotall: true}));
      });

      it("matches multiline ^ after a lone CR under anycrlf", () => {
        assert.deepEqual(
          match("^b", "a\rb", {multiline: true, newline: "anycrlf"}),
          {start: 2, end: 3},
        );
      });

      it("does not match multiline ^ between CR and LF under anycrlf", () => {
        assert.isNull(
          match("^\\n", "a\r\n", {multiline: true, newline: "anycrlf"}),
        );
      });

      it("matches \\Z before a final CRLF pair", () => {
        assert.deepEqual(match("a\\Z", "a\r\n", {newline: "crlf"}), {
          start: 0,
          end: 1,
        });
      });

      it("matches CRLF pair with \\R", () => {
        assert.deepEqual(match("\\R", "\r\n"), {start: 0, end: 2});
      });

      it("does not give back the CRLF pair matched by \\R", () => {
        assert.isNull(match("\\R\\n", "\r\n"));
      });

      it("excludes vertical tab from \\R with bsr_anycrlf", () => {
        assert.isNull(match("\\R", "\x0b", {bsrAnycrlf: true}));
      });

      it("matches vertical tab with \\R by default", () => {
        assert.deepEqual(match("\\R", "\x0b"), {start: 0, end: 1});
      });

      it("applies newline convention start verb", () => {
        assert.deepEqual(match("(*CR).", "\n"), {start: 0, end: 1});
      });

      it("matches any single char with \\C", () => {
        assert.deepEqual(match("\\C", "\n"), {start: 0, end: 1});
      });

      it("does not match \\C at the subject end", () => {
        assert.isNull(match("a\\C", "a"));
      });
    });

    describe("subroutine calls", () => {
      it("matches the called group content", () => {
        assert.deepEqual(match("(a)(?1)", "aa"), {start: 0, end: 2});
      });

      it("fails when the called content doesn't match", () => {
        assert.isNull(match("(a)(?1)", "ab"));
      });

      it("restores captures on call exit", () => {
        assert.deepEqual(matchFull("(a)(?1)", "aa"), {
          start: 0,
          end: 2,
          captures: [null, {start: 0, end: 1}],
        });
      });

      it("matches whole-pattern recursion", () => {
        assert.deepEqual(match("a(?R)?", "aaa"), {start: 0, end: 3});
      });

      it("binds anchors to the subject inside recursion", () => {
        assert.isNull(match("^a(?R)?$", "aa"));
      });

      it("matches anchored recursion base case", () => {
        assert.deepEqual(match("^a(?R)?$", "a"), {start: 0, end: 1});
      });

      it("matches balanced parentheses recursively", () => {
        assert.deepEqual(match("\\((?:[^()]|(?R))*\\)", "(a(b))"), {
          start: 0,
          end: 6,
        });
      });

      it("matches named call", () => {
        assert.deepEqual(match("(?<x>a)(?&x)", "aa"), {start: 0, end: 2});
      });

      it("backtracks into a call when the continuation fails", () => {
        assert.deepEqual(match("(a|ab)(?1)c", "aabc"), {start: 0, end: 4});
      });

      it("references outer captures after a call", () => {
        assert.deepEqual(matchFull("((a)|b)(?1)\\2", "aba"), {
          start: 0,
          end: 3,
          captures: [null, {start: 0, end: 1}, {start: 0, end: 1}],
        });
      });
    });

    describe("quantifiers", () => {
      it("matches greedily by default", () => {
        assert.deepEqual(match("a*", "aaa"), {start: 0, end: 3});
      });

      it("gives back greedy repetitions when needed", () => {
        assert.deepEqual(match("a*ab", "aaab"), {start: 0, end: 4});
      });

      it("matches lazily with minimal repetitions", () => {
        assert.deepEqual(match("a*?", "aaa"), {start: 0, end: 0});
      });

      it("grows lazy repetitions when needed", () => {
        assert.deepEqual(match("a*?b", "aaab"), {start: 0, end: 4});
      });

      it("matches exact count", () => {
        assert.deepEqual(match("a{2}", "aaa"), {start: 0, end: 2});
      });

      it("matches bounded range greedily", () => {
        assert.deepEqual(match("a{2,3}", "aaaa"), {start: 0, end: 3});
      });

      it("returns null below the minimum count", () => {
        assert.isNull(match("a{2,}", "a"));
      });

      it("matches optional item", () => {
        assert.deepEqual(match("ab?c", "ac"), {start: 0, end: 2});
      });

      it("matches quantified class", () => {
        assert.deepEqual(match("[ab]{2}", "xab"), {start: 1, end: 3});
      });

      it("swaps greediness with ungreedy option", () => {
        assert.deepEqual(match("a*", "aaa", {ungreedy: true}), {
          start: 0,
          end: 0,
        });
      });

      it("swaps laziness with ungreedy option", () => {
        assert.deepEqual(match("a*?", "aaa", {ungreedy: true}), {
          start: 0,
          end: 3,
        });
      });

      it("matches quantified astral char in unicode mode", () => {
        assert.deepEqual(match("😀+", "😀😀", {unicode: true}), {
          start: 0,
          end: 4,
        });
      });
    });

    describe("grapheme clusters", () => {
      it("matches a single char as one cluster", () => {
        assert.deepEqual(match("\\X", "ab"), {start: 0, end: 1});
      });

      it("matches a CRLF pair as one cluster in byte mode", () => {
        assert.deepEqual(match("^\\X$", "\r\n"), {start: 0, end: 2});
      });

      it("matches a combining sequence as one cluster", () => {
        assert.deepEqual(match("^\\X$", "é", {unicode: true}), {
          start: 0,
          end: 2,
        });
      });

      it("matches quantified clusters", () => {
        assert.deepEqual(match("^\\X{2}$", "éx", {unicode: true}), {
          start: 0,
          end: 3,
        });
      });

      it("does not match at the subject end", () => {
        assert.isNull(match("a\\X", "a"));
      });
    });

    describe("groups and options", () => {
      it("matches quantified non-capturing group", () => {
        assert.deepEqual(match("(?:ab)+c", "ababc"), {start: 0, end: 5});
      });

      it("stops empty repetitions of a group", () => {
        assert.deepEqual(match("(?:a?)*b", "b"), {start: 0, end: 1});
      });

      it("applies caseless option group within its scope", () => {
        assert.deepEqual(match("(?i:a)b", "Ab"), {start: 0, end: 2});
      });

      it("ends caseless option group scope at its close", () => {
        assert.isNull(match("(?i:a)b", "AB"));
      });

      it("applies inline option setting to the rest of the group", () => {
        assert.deepEqual(match("a(?i)b", "aB"), {start: 0, end: 2});
      });

      it("leaks inline option setting into subsequent branches", () => {
        assert.deepEqual(match("a(?i)b|c", "C"), {start: 0, end: 1});
      });

      it("applies scoped ungreedy option", () => {
        assert.deepEqual(match("(?U:a*)", "aaa"), {start: 0, end: 0});
      });
    });

    describe("literals", () => {
      it("matches literal at a later position", () => {
        assert.deepEqual(match("b", "abc"), {start: 1, end: 2});
      });

      it("matches multi-char sequence", () => {
        assert.deepEqual(match("bc", "abcd"), {start: 1, end: 3});
      });

      it("returns null without a match", () => {
        assert.isNull(match("x", "abc"));
      });

      it("matches empty pattern at the start", () => {
        assert.deepEqual(match("", "a"), {start: 0, end: 0});
      });

      it("matches caseless literals", () => {
        assert.deepEqual(match("abc", "xABC", {caseless: true}), {
          start: 1,
          end: 4,
        });
      });

      it("matches non-ASCII literal in unicode mode", () => {
        assert.deepEqual(match("é", "xé", {unicode: true}), {
          start: 1,
          end: 2,
        });
      });

      it("matches astral literal as one char in unicode mode", () => {
        assert.deepEqual(match("😀", "a😀", {unicode: true}), {
          start: 1,
          end: 3,
        });
      });
    });
  });
});
