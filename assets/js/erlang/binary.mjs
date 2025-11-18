"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// Base class and factory
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
        const patterns = patternData.patterns.map(p => Bitstring.fromBytes(p));
        return new AhoCorasickMatcher(Type.list(patterns));
      }
    }

    Interpreter.raiseArgumentError("pattern must be a binary or a list of binaries");
  }

  // Collect all non-overlapping matches using a findNext callback
  // findNext(pos) should return a match object or null
  collectMatches(subjectBytes, findNext, limit = Infinity) {
    const matches = [];
    let pos = 0;
    let lastEnd = 0;

    while (matches.length < limit) {
      const match = findNext(pos);
      if (!match) break;

      // Only keep non-overlapping matches
      if (match.start >= lastEnd) {
        matches.push(match);
        lastEnd = match.end;
      }

      pos = match.start + 1; // Move forward by 1 to find overlapping matches
    }

    return matches;
  }

  // Split a subject into parts based on matches
  splitWithMatches(subject, matches, global) {
    const subjectBytes = Erlang_Binary.validate(subject);

    if (matches.length === 0) {
      return Type.list([subject]);
    }

    const parts = [];
    let lastEnd = 0;

    const matchesToUse = global ? matches : matches.slice(0, 1);

    for (const match of matchesToUse) {
      // Add the part before this match
      if (match.start > lastEnd) {
        parts.push(Bitstring.fromBytes(subjectBytes.subarray(lastEnd, match.start)));
      } else if (match.start === lastEnd) {
        // Empty part
        parts.push(Bitstring.fromBytes(new Uint8Array(0)));
      }

      lastEnd = match.end;
    }

    // Add the remaining part after the last match
    if (lastEnd < subjectBytes.length) {
      parts.push(Bitstring.fromBytes(subjectBytes.subarray(lastEnd)));
    } else {
      // Empty part at the end
      parts.push(Bitstring.fromBytes(new Uint8Array(0)));
    }

    return Type.list(parts);
  }
}

// Boyer-Moore pattern matching class for single patterns
class BoyerMooreMatcher extends Matcher {
  constructor(pattern) {
    super();
    this.pattern = Erlang_Binary.validate(pattern);
    this.badShift = this.#computeBadShift();
  }

  #computeBadShift() {
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

  // Find next match starting from startPos
  // Returns match object or null if no match found
  #findMatch(subjectBytes, startPos = 0) {
    const patternLength = this.pattern.length;
    const subjectLength = subjectBytes.length;

    if (patternLength === 0 || patternLength > subjectLength) {
      return null;
    }

    let i = startPos;

    while (i <= subjectLength - patternLength) {
      let j = patternLength - 1;

      // Match from right to left
      while (j >= 0 && this.pattern[j] === subjectBytes[i + j]) {
        j--;
      }

      if (j < 0) {
        // Found a match
        return {
          start: i,
          end: i + patternLength,
          length: patternLength
        };
      } else {
        // Mismatch - use bad character rule
        const badChar = subjectBytes[i + j];
        const shift = this.badShift.get(badChar) || patternLength;
        i += Math.max(1, shift);
      }
    }

    return null;
  }

  split(subject, global = false) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const matches = this.collectMatches(
      subjectBytes,
      (pos) => this.#findMatch(subjectBytes, pos),
      global ? Infinity : 1
    );
    return this.splitWithMatches(subject, matches, global);
  }

  match(subject) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const match = this.#findMatch(subjectBytes, 0);

    if (!match) {
      return Type.atom("nomatch");
    }

    return Type.tuple([Type.integer(match.start), Type.integer(match.length)]);
  }

  matches(subject) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const matches = this.collectMatches(
      subjectBytes,
      (pos) => this.#findMatch(subjectBytes, pos)
    );

    return Type.list(
      matches.map(match =>
        Type.tuple([Type.integer(match.start), Type.integer(match.length)])
      )
    );
  }

  toTuple() {
    return Type.tuple([
      Type.atom("bm"),
      {
        algorithm: "boyer_moore",
        pattern: this.pattern,
        badShift: this.badShift
      }
    ]);
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

    this.patterns = patternList.data.map(item =>
      Erlang_Binary.validate(item)
    );

    this.automaton = this.#buildTrie();
    this.#buildFailureLinks(this.automaton);
  }

  #buildTrie() {
    const root = { transitions: new Map(), outputs: [], failure: null };
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
            failure: null
          });
        }

        currentNode = currentNode.transitions.get(byte);
      }

      // Mark this node as an output for this pattern
      currentNode.outputs.push({
        patternIdx: patternIdx,
        length: pattern.length
      });
    }

    return root;
  }

  #buildFailureLinks(root) {
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
          childNode.outputs = childNode.outputs.concat(childNode.failure.outputs);
        }
      }
    }
  }

  // Find next match starting from startPos with given automaton state
  // Returns { match, state } or null if no match found
  #findMatch(subjectBytes, startPos = 0, startNode = this.automaton) {
    let currentNode = startNode;

    for (let i = startPos; i < subjectBytes.length; i++) {
      const byte = subjectBytes[i];

      // Follow failure links until we find a transition or reach root
      while (currentNode !== this.automaton && !currentNode.transitions.has(byte)) {
        currentNode = currentNode.failure;
      }

      // Try to transition
      if (currentNode.transitions.has(byte)) {
        currentNode = currentNode.transitions.get(byte);
      } else {
        currentNode = this.automaton;
      }

      // Check if current node has any outputs (pattern matches)
      if (currentNode.outputs.length > 0) {
        // Return the longest match at this position
        const output = currentNode.outputs[0]; // outputs are inherited, first is usually longest
        return {
          match: {
            start: i - output.length + 1,
            end: i + 1,
            length: output.length,
            patternIdx: output.patternIdx
          },
          state: {
            pos: i + 1,
            node: currentNode
          }
        };
      }
    }

    return null;
  }

  split(subject, global = false) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const matches = this.collectMatches(
      subjectBytes,
      (pos) => {
        const result = this.#findMatch(subjectBytes, pos, this.automaton);
        return result ? result.match : null;
      },
      global ? Infinity : 1
    );
    return this.splitWithMatches(subject, matches, global);
  }

  match(subject) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const result = this.#findMatch(subjectBytes, 0, this.automaton);

    if (!result) {
      return Type.atom("nomatch");
    }

    const { match } = result;
    return Type.tuple([Type.integer(match.start), Type.integer(match.length)]);
  }

  matches(subject) {
    const subjectBytes = Erlang_Binary.validate(subject);
    const matches = this.collectMatches(
      subjectBytes,
      (pos) => {
        const result = this.#findMatch(subjectBytes, pos, this.automaton);
        return result ? result.match : null;
      }
    );

    return Type.list(
      matches.map(match =>
        Type.tuple([Type.integer(match.start), Type.integer(match.length)])
      )
    );
  }

  toTuple() {
    return Type.tuple([
      Type.atom("ac"),
      {
        algorithm: "aho_corasick",
        patterns: this.patterns
      }
    ]);
  }
}

const Erlang_Binary = {
  "split/2": (subject, pattern) => {
    return Erlang_Binary["split/3"](subject, pattern, Type.list([]));
  },

  "split/3": (subject, pattern, options) => {
    // Parse options
    let global = false;

    if (Type.isList(options)) {
      for (const opt of options.data) {
        if (Type.isAtom(opt) && opt.value === "global") {
          global = true;
        }
        // TODO: Add support for scope, trim, trim_all options
      }
    }

    const patternObj = Matcher.create(pattern);
    return patternObj.split(subject, global);
  },

  "match/2": (subject, pattern) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.match(subject);
  },

  "matches/2": (subject, pattern) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.matches(subject);
  },

  "compile_pattern/1": (pattern) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.toTuple();
  },

  validate: (bitstring) => {
    if (!Type.isBitstring(bitstring)) {
      Interpreter.raiseArgumentError(`must be a binary`);
    }

    Bitstring.maybeSetBytesFromText(bitstring);

    if (bitstring.leftoverBitCount !== 0) {
      Interpreter.raiseArgumentError(`must be a binary (not a bitstring)`);
    }

    return bitstring.bytes;
  }
};

export default Erlang_Binary;