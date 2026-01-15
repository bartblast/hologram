"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang_Lists from "./lists.mjs";
import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Binary = {
  // Start at/2
  "at/2": (subject, pos) => {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    if (!Type.isInteger(pos)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (pos.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);

    if (pos.value >= subject.bytes.length) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.integer(subject.bytes[pos.value]);
  },
  // End at/2
  // Deps: []

  // Start compile_pattern/1
  "compile_pattern/1": (pattern) => {
    if (Type.isBinary(pattern)) {
      return Erlang_Binary["_boyer_moore_pattern_matcher/1"](pattern);
    } else if (
      Type.isList(pattern) &&
      pattern.data.length > 0 &&
      pattern.data.every((i) => Type.isBinary(i))
    ) {
      return pattern.data.length == 1
        ? Erlang_Binary["_boyer_moore_pattern_matcher/1"](pattern.data[0])
        : Erlang_Binary["_aho_corasick_pattern_matcher/1"](pattern);
    }

    Interpreter.raiseArgumentError("is not a valid pattern");
  },
  // End compile_pattern/1
  // Deps: [:binary._aho_corasick_pattern_matcher/1, :binary._boyer_moore_pattern_matcher/1]

  // Start copy/2
  "copy/2": (subject, count) => {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    if (!Type.isInteger(count)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (count.value < 0n) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "out of range"),
      );
    }

    if (count.value === 0n) {
      return Bitstring.fromText("");
    }

    if (count.value === 1n) {
      return subject;
    }

    const countNumber = Number(count.value);

    if (subject.text !== null) {
      return Bitstring.fromText(subject.text.repeat(countNumber));
    }

    if (subject.bytes.length === 0) {
      return Bitstring.fromText("");
    }

    const sourceBytes = subject.bytes;
    const sourceLength = sourceBytes.length;
    const totalLength = sourceLength * countNumber;
    const resultBytes = new Uint8Array(totalLength);

    for (let i = 0; i < countNumber; i++) {
      resultBytes.set(sourceBytes, i * sourceLength);
    }

    return Bitstring.fromBytes(resultBytes);
  },
  // End copy/2
  // Deps: []

  // Start first/1
  "first/1": (subject) => {
    if (!Type.isBinary(subject)) {
      const message = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, message),
      );
    }

    if (Bitstring.isEmpty(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "a zero-sized binary is not allowed",
        ),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);

    return Type.integer(subject.bytes[0]);
  },
  // End first/1
  // Deps: []

  // Start match/3
  match: (subject, pattern, options) => {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    const compiledPattern = Erlang_Binary["compile_pattern/1"](pattern);

    if (compiledPattern.type == "bm") {
      return Erlang_Binary["_boyer_moore_search/3"](
        subject,
        compiledPattern,
        options,
      );
    } else if (compiledPattern.type == "ac") {
      return Erlang_Binary["_aho_corasick_search/3"](
        subject,
        compiledPattern,
        options,
      );
    }

    return Type.atom("nomatch");
  },
  // End match/3
  // Deps: [:binary.compile_pattern/1, :binary._boyer_moore_search/3, :binary._aho_corasick_search/3, :binary._parse_search_options/1]

  // Boyer-Moore matcher implementation for single patterns
  // Start _boyer_moore_pattern_matcher/1
  _boyer_moore_pattern_matcher: (pattern) => {
    Bitstring.maybeSetBytesFromText(pattern);

    if (pattern.bytes.length == 0) {
      Interpreter.raiseArgumentError("is not a valid pattern");
    }

    let badShift;
    let compiledPattern = ERTS.binaryPatternRegistry.get(pattern);
    if (compiledPattern) {
      badShift = compiledPattern.badShift;
    } else {
      badShift = {};

      const length = pattern.bytes.length - 1;

      // Seed the badShift object with an initial value of -1 for each byte
      for (let i = 0; i < 256; i++) {
        badShift[i] = -1;
      }

      // Overwrite with the actual value for each byte in the pattern
      pattern.bytes.forEach((byte, index) => {
        badShift[byte] = length - index;
      });

      compiledPattern = {type: "bm", ref, badShift};
    }

    const ref = Erlang["make_ref/0"]();
    ERTS.binaryPatternRegistry.put(pattern, compiledPattern);

    return Type.tuple([Type.atom("bm"), ref]);
  },
  // End _boyer_moore_pattern_matcher/1
  // Deps: [:erlang.make_ref/0]

  // Start _boyer_moore_search/3
  _boyer_moore_search: (subject, compiledPattern, options) => {
    const searchOptions = Erlang_Binary["_parse_search_opts/1"](options);

    let index = Math.floor(searchOptions.start < 0 ? 0 : searchOptions.start);
    const pattern = compiledPattern.pattern;
    const patternLastIndex = pattern.length - 1;
    const badShift = compiledPattern.badShift;

    const maxIndex =
      searchOptions.length > 0
        ? searchOptions.length
        : subject.length - pattern.length;

    while (index <= maxIndex) {
      let patternIndex = 0;
      while (pattern[patternIndex] === subject[patternIndex + index]) {
        if (patternIndex === patternLastIndex) {
          return {index, length: pattern.length};
        }
        patternIndex++;
      }

      const current = subject[index + patternLastIndex];
      if (badShift[current]) {
        index += badShift[current];
      } else {
        index++;
      }
    }
    return false;
  },
  // End _boyer_moore_search/3
  // Deps: []

  // Aho-Corasick matcher implementation for multiple patterns
  // Start _aho_corasick_pattern_matcher/1
  _aho_corasick_pattern_matcher: (patterns) => {
    let rootNode;
    let compiledPattern = ERTS.binaryPatternRegistry.get(patterns);
    if (compiledPattern) {
      rootNode = compiledPattern.rootNode;
    } else {
      rootNode = {
        children: new Map(),
        output: [],
        failure: null,
      };

      // Build tries for each pattern
      patterns.data.forEach((pattern) => {
        Bitstring.maybeSetBytesFromText(pattern);

        if (pattern.bytes.length === 0) {
          Interpreter.raiseArgumentError("is not a valid pattern");
        }

        let node = rootNode;
        pattern.bytes.forEach((byte) => {
          if (!node.children.has(byte)) {
            node.children.set(byte, {
              children: new Map(),
              output: [],
              failure: null,
            });
          }
          node = node.children.get(byte);
        });
        node.output.push(pattern);
      });

      // Add failures
      const queue = [];

      for (const [_byte, childNode] of rootNode.children) {
        childNode.failure = rootNode;
        queue.push(childNode);
      }

      while (queue.length > 0) {
        const node = queue.shift();

        for (const [byte, childNode] of node.children) {
          queue.push(childNode);

          let failureNode = node.failure;
          while (failureNode !== null && !failureNode.children.has(byte)) {
            failureNode = failureNode.failure;
          }

          childNode.failure =
            failureNode === null ? rootNode : failureNode.children.get(byte);

          childNode.output = childNode.output.concat(childNode.failure.output);
        }
      }
      compiledPattern = {type: "ac", ref, rootNode};
    }

    const ref = Erlang["make_ref/0"]();
    ERTS.binaryPatternRegistry.put(patterns, compiledPattern);

    return Type.tuple([Type.atom("ac"), ref]);
  },
  // End _aho_corasick_pattern_matcher/1
  // Deps: [:erlang.make_ref/0]

  // Start _aho_corasick_search/3
  _aho_corasick_search: (subject, compiledPattern, options) => {
    const searchOptions = Erlang_Binary["_parse_search_opts/1"](options);
    const index = Math.floor(searchOptions.start < 0 ? 0 : searchOptions.start);
    const maxIndex = Math.floor(
      searchOptions.length > 0 ? searchOptions.length : subject.length,
    );

    let currentNode = compiledPattern.rootNode;

    for (let i = index; i < maxIndex; i++) {
      const char = subject[i];

      while (currentNode !== null && !currentNode.children[char]) {
        currentNode = currentNode.failure;
      }

      if (currentNode) {
        currentNode.children[char] || compiledPattern.rootNode;
      } else {
        compiledPattern.rootNode;
      }

      const resultLength = currentNode.output.length;
      const foundIndex = i - resultLength + 1;
      return {foundIndex, resultLength};
    }
    return false;
  },
  // End _aho_corasick_search/3
  // Deps: []

  // Start _parse_search_opts/1
  "_parse_search_opts/1": (opts) => {
    if (!Type.isList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("invalid options"),
      );
    }

    if (Type.isImproperList(opts)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg("invalid options"),
      );
    }

    const scopeTuple = Erlang_Lists["keyfind/3"](
      Type.atom("scope"),
      Type.integer(1),
      opts,
    );

    if (scopeTuple) {
      const innerTuple = scopeTuple.data[1];
      const start = innerTuple.data[0];
      const length = innerTuple.data[1];
      if (Type.isInteger(start) && Type.isInteger(length)) {
        return {start, length};
      } else {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg("invalid options"),
        );
      }
    } else {
      return {start: 0, length: -1};
    }
  },
  // End _parse_search_opts/1
  // Deps: [:lists.keyfind/3]
};

export default Erlang_Binary;
