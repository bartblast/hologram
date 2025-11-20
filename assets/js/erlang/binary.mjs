"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.
// Base class and factory for Matchers (used in match, matches, replace, and split)

// Matcher base class to reduce code duplication
class Matcher {
  // Create pattern object from pattern or compiled pattern
  static create(pattern) {
    if (Type.isBitstring(pattern)) {
      return new BoyerMooreMatcher(pattern);
    } else if (Type.isList(pattern)) {
      return new AhoCorasickMatcher(pattern);
    } else if (Type.isTuple(pattern) && pattern.data.length === 2) {
      // Compiled pattern tuple: {algo_atom, pattern_data}
      const [algoAtom, patternData] = pattern.data;

      if (!Type.isAtom(algoAtom)) {
        Interpreter.raiseArgumentError("invalid compiled pattern format");
      }

      if (algoAtom.value === "bm") {
        const originalPattern = Bitstring.fromBytes(patternData.pattern);
        return new BoyerMooreMatcher(originalPattern);
      } else if (algoAtom.value === "ac") {
        const patterns = patternData.patterns.map((p) =>
          Bitstring.fromBytes(p),
        );
        return new AhoCorasickMatcher(Type.list(patterns));
      }
    }

    Interpreter.raiseArgumentError(
      "pattern must be a binary or a list of binaries",
    );
  }

  // Validate that a value is a binary (bitstring with no leftover bits) and return its bytes
  validate_binary(bitstring) {
    if (!Type.isBitstring(bitstring)) {
      Interpreter.raiseArgumentError(`must be a binary`);
    }

    Bitstring.maybeSetBytesFromText(bitstring);

    if (bitstring.leftoverBitCount !== 0) {
      Interpreter.raiseArgumentError(`must be a binary (not a bitstring)`);
    }

    return bitstring.bytes;
  }
}

// Boyer-Moore pattern matching class for single patterns
class BoyerMooreMatcher extends Matcher {
  constructor(pattern) {
    super();
    this.pattern = this.validate_binary(pattern);
    this.badShift = this.computeBadShift();
  }

  toTuple() {
    return Type.tuple([
      Type.atom("bm"),
      {
        algorithm: "boyer_moore",
        pattern: this.pattern,
      },
    ]);
  }

  computeBadShift() {
    const badShift = new Map();
    const patternLength = this.pattern.length;

    // Initialize all characters to pattern length (default shift)
    for (let i = 0; i < 256; i++) {
      badShift.set(i, patternLength);
    }

    // Fill in the actual shifts for characters in the pattern
    for (let i = 0; i < patternLength - 1; i++) {
      badShift.set(this.pattern[i], patternLength - 1 - i);
    }

    return badShift;
  }
}

// Aho-Corasick pattern matching class for multiple patterns
class AhoCorasickMatcher extends Matcher {
  constructor(patternList) {
    super();

    // Validate and parse the pattern list
    if (!Type.isList(patternList)) {
      Interpreter.raiseArgumentError("pattern must be a list of binaries");
    }

    if (patternList.data.length === 0) {
      Interpreter.raiseArgumentError("pattern list must not be empty");
    }

    this.patterns = patternList.data.map((item) => this.validate_binary(item));

    this.automaton = this.buildTrie();
    this.buildFailureLinks(this.automaton);
  }

  toTuple() {
    return Type.tuple([
      Type.atom("ac"),
      {
        algorithm: "aho_corasick",
        patterns: this.patterns,
      },
    ]);
  }

  buildTrie() {
    const root = {transitions: new Map(), outputs: [], failure: null};
    let nodeId = 0;

    // Insert all patterns into the trie
    for (let patternIdx = 0; patternIdx < this.patterns.length; patternIdx++) {
      const pattern = this.patterns[patternIdx];
      let currentNode = root;

      for (let i = 0; i < pattern.length; i++) {
        const byte = pattern[i];

        if (!currentNode.transitions.has(byte)) {
          currentNode.transitions.set(byte, {
            id: ++nodeId,
            transitions: new Map(),
            outputs: [],
            failure: null,
          });
        }

        currentNode = currentNode.transitions.get(byte);
      }

      // Mark this node as an output for this pattern
      currentNode.outputs.push({
        patternIdx: patternIdx,
        length: pattern.length,
      });
    }

    return root;
  }

  buildFailureLinks(root) {
    const queue = [];

    // All depth-1 nodes fail to root
    for (const [_byte, node] of root.transitions) {
      node.failure = root;
      queue.push(node);
    }

    // BFS to compute failure links
    while (queue.length > 0) {
      const currentNode = queue.shift();

      for (const [byte, childNode] of currentNode.transitions) {
        queue.push(childNode);

        // Find failure link
        let failureNode = currentNode.failure;

        while (failureNode !== null && !failureNode.transitions.has(byte)) {
          failureNode = failureNode.failure;
        }

        if (failureNode === null) {
          childNode.failure = root;
        } else {
          childNode.failure = failureNode.transitions.get(byte);
          // Inherit outputs from failure link
          childNode.outputs = childNode.outputs.concat(
            childNode.failure.outputs,
          );
        }
      }
    }
  }
}

const Erlang_Binary = {
  // Start at/2
  "at/2": function (subject, pos) {
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
    const patternObj = Matcher.create(pattern);
    return patternObj.toTuple();
  },
  // End compile_pattern/1
  // Deps: []
};

export default Erlang_Binary;
