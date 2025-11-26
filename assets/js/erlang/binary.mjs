"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.
// Base class and factory for Matchers (used in match, matches, replace, and split)

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
      return Erlang_Binary._boyerMoorePatternMatcher(pattern);
    } else if (
      Type.isList(pattern) &&
      pattern.data.length > 0 &&
      pattern.data.every((i) => Type.isBinary(i))
    ) {
      return Erlang_Binary._ahoCorasickPatternMatcher(pattern);
    } else if (Type.isCompiledPattern(pattern)) {
      return pattern;
    }

    Interpreter.raiseArgumentError("is not a valid pattern");
  },
  // End compile_pattern/1
  // Deps: [Erlang_Binary._ahoCorasickPatternMatcher, Erlang_Binary._boyerMoorePatternMatcher]

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

  // Start _boyerMoorePatternMatcher
  // Boyer-Moore matcher implementation for single patterns
  _boyerMoorePatternMatcher: (pattern) => {
    Bitstring.maybeSetBytesFromText(pattern);
    const length = pattern.bytes.length - 1;

    // Seed badShift with initial values
    const badShift = Object.fromEntries(
      Array.from({length: 256}, (_, i) => [i, -1]),
    );

    // Assign bad shift values for each byte in the pattern
    pattern.bytes.forEach((byte, index) => {
      badShift[byte] = length - index;
    });

    return Type.tuple([
      Type.atom("bm"),
      Type.reference({
        algorithm: "boyer_moore",
        words: pattern,
        badShift: badShift,
      }),
    ]);
  },
  // End _boyerMoorePatternMatcher
  // Deps: []

  // Start _ahoCorasickPatternMatcher
  // Aho-Corasick matcher implementation for multiple patterns
  _ahoCorasickPatternMatcher: (patterns) => {
    const root = {
      children: new Map(),
      output: [],
      failure: null,
    };

    // Build tries for each pattern
    patterns.data.forEach((pattern) => {
      Bitstring.maybeSetBytesFromText(pattern);
      let node = root;
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

    for (const [_byte, childNode] of root.children) {
      childNode.failure = root;
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
          failureNode === null ? root : failureNode.children.get(byte);

        childNode.output = childNode.output.concat(childNode.failure.output);
      }
    }

    return Type.tuple([
      Type.atom("ac"),
      Type.reference({
        algorithm: "aho_corasick",
        words: patterns,
        trie: root,
      }),
    ]);
  },
  // End _ahoCorasickPatternMatcher
  // Deps: []
};

export default Erlang_Binary;
