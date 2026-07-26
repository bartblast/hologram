"use strict";

import RegexAnalyzer from "./regex_analyzer.mjs";
import RegexInterpreter from "./regex_interpreter.mjs";
import RegexParser from "./regex_parser.mjs";
import RegexTranslator from "./regex_translator.mjs";

// Facade over the regex machinery: compiles PCRE2 patterns into matchable
// entries and matches them against JS strings, hiding the native/interpreted
// engine split. Byte-level subject encoding and Erlang term shaping are the
// callers' concern.
export default class RegexEngine {
  // Compiles a PCRE2 pattern source into a matchable entry, routed to the
  // native JS RegExp engine when every construct translates with identical
  // semantics, and to the interpreter otherwise.
  // Raises RegexParseError when the pattern is not valid PCRE2 syntax.
  static compile(source, opts = {}) {
    const ast = RegexParser.parse(source, opts);
    const groupMap = RegexAnalyzer.buildGroupMap(ast);
    const strategy = RegexAnalyzer.route(ast, groupMap, opts);

    const compiled = {
      ast: ast,
      groupMap: groupMap,
      groupMapping: null,
      opts: opts,
      regexp: null,
      source: source,
      strategy: strategy,
    };

    if (strategy === "native") {
      const translated = RegexTranslator.translate(ast, opts);

      // The d flag provides match indices, the g flag makes lastIndex control
      // the match start position
      compiled.groupMapping = translated.groupMapping;
      compiled.regexp = new RegExp(translated.source, `${translated.flags}dg`);
    }

    return compiled;
  }

  // Matches a compiled entry against a subject string, scanning forward from
  // the start position. Returns {start, end, captures} with PCRE2 group
  // numbering, or null. Positions are JS string indices.
  static match(compiled, subject, runOpts = {}) {
    const startPosition = runOpts.startPosition ?? 0;

    if (compiled.strategy === "native") {
      compiled.regexp.lastIndex = startPosition;

      const jsMatch = compiled.regexp.exec(subject);

      if (jsMatch === null) return null;

      const captures = [null];

      for (let number = 1; number <= compiled.groupMap.count; number++) {
        const jsNumber = compiled.groupMapping.get(number);
        const indices = jsMatch.indices[jsNumber];

        captures.push(
          indices === undefined ? null : {start: indices[0], end: indices[1]},
        );
      }

      return {
        start: jsMatch.indices[0][0],
        end: jsMatch.indices[0][1],
        captures: captures,
      };
    }

    return RegexInterpreter.match(compiled.ast, subject, {
      ...compiled.opts,
      groupMap: compiled.groupMap,
      startPosition: startPosition,
    });
  }
}
