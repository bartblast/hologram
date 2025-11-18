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
  #collectMatches(subjectBytes, findNext, limit = Infinity, scope = null) {
    const matches = [];
    const scopeStart = scope ? scope.start : 0;
    const scopeEnd = scope ? scope.start + scope.length : subjectBytes.length;

    let pos = scopeStart;
    let lastEnd = scopeStart;

    while (matches.length < limit && pos < scopeEnd) {
      const match = findNext(pos, scopeEnd);
      if (!match) break;

      // Check if match is within scope
      if (match.start < scopeStart || match.start >= scopeEnd) {
        break;
      }

      // Only keep non-overlapping matches
      if (match.start >= lastEnd) {
        matches.push(match);
        lastEnd = match.end;
      }

      pos = match.start + 1; // Move forward by 1 to find overlapping matches
    }

    return matches;
  }

  // Process matches generically - used by both split and replace
  // processParts callback: (beforePart, match, matchedBytes) => parts to add at match location
  #processMatches(subject, matches, opts, processParts) {
    const subjectBytes = Matcher.validate_binary(subject);

    if (matches.length === 0) {
      return { parts: [subjectBytes], allBytes: true };
    }

    const parts = [];
    let lastEnd = 0;
    const matchesToUse = opts.global ? matches : matches.slice(0, 1);

    for (const match of matchesToUse) {
      // Add the part before this match
      const beforePart = match.start > lastEnd
        ? subjectBytes.subarray(lastEnd, match.start)
        : new Uint8Array(0);

      // Get the matched bytes
      const matchedBytes = subjectBytes.subarray(match.start, match.end);

      // Let the caller determine what parts to add
      const matchParts = processParts(beforePart, match, matchedBytes);
      parts.push(...matchParts);

      lastEnd = match.end;
    }

    // Add the remaining part after the last match
    const remainingPart = lastEnd < subjectBytes.length
      ? subjectBytes.subarray(lastEnd)
      : new Uint8Array(0);
    parts.push(remainingPart);

    return { parts, allBytes: true };
  }

  // Split a subject into parts based on matches
  #splitWithMatches(subject, matches, opts) {
    if (matches.length === 0) {
      return Type.list([subject]);
    }

    const { parts } = this.#processMatches(subject, matches, opts, (beforePart, _match, _matchedBytes) => {
      // For split, we just want the part before the match (the matched part itself is discarded)
      return [Bitstring.fromBytes(beforePart)];
    });

    // Convert Uint8Array parts to Bitstring for the last remaining part
    const bitstringParts = parts.map((part, idx) =>
      idx === parts.length - 1 && part instanceof Uint8Array
        ? Bitstring.fromBytes(part)
        : part
    );

    return this.#applyTrimOptions(bitstringParts, opts);
  }

  // Apply trim or trim_all options to split results
  #applyTrimOptions(parts, opts) {
    let result = parts;

    if (opts.trim_all) {
      // Remove all empty parts
      result = parts.filter(part => part.bytes.length > 0);
    } else if (opts.trim) {
      // Remove trailing empty parts
      while (result.length > 0 && result[result.length - 1].bytes.length === 0) {
        result.pop();
      }
    }

    return Type.list(result);
  }

  // Apply function replacement to matched part
  #applyFunctionReplacement(replacement, matchedBytes) {
    const matchedBitstring = Bitstring.fromBytes(matchedBytes);
    const result = Interpreter.callAnonymousFunction(replacement, [matchedBitstring]);

    if (!Type.isBitstring(result)) {
      Interpreter.raiseArgumentError("replacement function must return a binary");
    }

    return Matcher.validate_binary(result);
  }

  // Insert matched bytes into replacement at specified positions
  #insertMatchedIntoReplacement(replacementBytes, matchedBytes, positions) {
    // Validate positions first
    for (const pos of positions) {
      if (pos > replacementBytes.length) {
        Interpreter.raiseArgumentError("insert_replaced position is greater than replacement size");
      }
    }

    // Build replacement with insertions
    const replacementParts = [];
    let lastPos = 0;

    // Sort positions in ascending order for building
    const sortedPositions = [...positions].sort((a, b) => a - b);

    for (const pos of sortedPositions) {
      replacementParts.push(replacementBytes.subarray(lastPos, pos));
      replacementParts.push(matchedBytes);
      lastPos = pos;
    }
    replacementParts.push(replacementBytes.subarray(lastPos));

    return Matcher.#concatenateBytes(replacementParts);
  }

  // Calculate replacement bytes for a match (handles both function and binary replacements)
  #calculateReplacement(replacement, matchedBytes, opts, isFunction) {
    if (isFunction) {
      return this.#applyFunctionReplacement(replacement, matchedBytes);
    }

    // Binary replacement
    let replacementBytes = Matcher.validate_binary(replacement);

    // Handle insert_replaced option for binary replacements
    if (opts.insert_replaced && opts.insert_replaced.length > 0) {
      replacementBytes = this.#insertMatchedIntoReplacement(
        replacementBytes,
        matchedBytes,
        opts.insert_replaced
      );
    }

    return replacementBytes;
  }

  // Replace matched parts in the subject with replacement
  #replaceWithMatches(subject, matches, replacement, opts) {
    if (matches.length === 0) {
      return subject;
    }

    const isFunction = Type.isAnonymousFunction(replacement);
    if (!isFunction && !Type.isBitstring(replacement)) {
      Interpreter.raiseArgumentError("replacement must be a binary or a function");
    }

    const { parts } = this.#processMatches(subject, matches, opts, (beforePart, _match, matchedBytes) => {
      const replacementBytes = this.#calculateReplacement(replacement, matchedBytes, opts, isFunction);
      return [beforePart, replacementBytes];
    });

    return Bitstring.fromBytes(Matcher.#concatenateBytes(parts));
  }

  // Helper to concatenate byte arrays efficiently
  static #concatenateBytes(parts) {
    const totalLength = parts.reduce((sum, part) => sum + part.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const part of parts) {
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  }

  // Helper to calculate scope boundaries
  #getScopeBounds(scope, subjectLength) {
    const scopeStart = scope ? scope.start : 0;
    const scopeEnd = scope ? scope.start + scope.length : subjectLength;
    return { scopeStart, scopeEnd };
  }

  // Validate that a value is a binary (bitstring with no leftover bits) and return its bytes
  static validate_binary(bitstring) {
    if (!Type.isBitstring(bitstring)) {
      Interpreter.raiseArgumentError(`must be a binary`);
    }

    Bitstring.maybeSetBytesFromText(bitstring);

    if (bitstring.leftoverBitCount !== 0) {
      Interpreter.raiseArgumentError(`must be a binary (not a bitstring)`);
    }

    return bitstring.bytes;
  }

  // Abstract method - subclasses must implement
  // Returns match object or null
  findMatch(_subjectBytes, _startPos, _endPos) {
    throw new Error("Subclasses must implement findMatch");
  }

  // Generic split implementation
  split(subject, options) {
    const opts = this.#parseOptions(options);
    const subjectBytes = Matcher.validate_binary(subject);
    const matches = this.#collectMatches(
      subjectBytes,
      (pos, endPos) => this.findMatch(subjectBytes, pos, endPos),
      opts.global ? Infinity : 1,
      opts.scope
    );
    return this.#splitWithMatches(subject, matches, opts);
  }

  // Generic match implementation
  match(subject, options) {
    const opts = this.#parseOptions(options);
    const subjectBytes = Matcher.validate_binary(subject);
    const { scopeStart, scopeEnd } = this.#getScopeBounds(opts.scope, subjectBytes.length);
    const match = this.findMatch(subjectBytes, scopeStart, scopeEnd);

    if (!match) {
      return Type.atom("nomatch");
    }

    return Type.tuple([Type.integer(match.start), Type.integer(match.length)]);
  }

  // Generic matches implementation
  matches(subject, options) {
    const opts = this.#parseOptions(options);
    const subjectBytes = Matcher.validate_binary(subject);
    const matches = this.#collectMatches(
      subjectBytes,
      (pos, endPos) => this.findMatch(subjectBytes, pos, endPos),
      Infinity,
      opts.scope
    );

    return Type.list(
      matches.map(match =>
        Type.tuple([Type.integer(match.start), Type.integer(match.length)])
      )
    );
  }

  // Generic replace implementation
  replace(subject, replacement, options) {
    const opts = this.#parseOptions(options);
    const subjectBytes = Matcher.validate_binary(subject);
    const matches = this.#collectMatches(
      subjectBytes,
      (pos, endPos) => this.findMatch(subjectBytes, pos, endPos),
      opts.global ? Infinity : 1,
      opts.scope
    );
    return this.#replaceWithMatches(subject, matches, replacement, opts);
  }

  // Parse scope option {start, length}
  #parseScope(value) {
    if (!Type.isTuple(value) || value.data.length !== 2) return null;

    const start = Type.isInteger(value.data[0]) ? Number(value.data[0].value) : 0;
    const length = Type.isInteger(value.data[1]) ? Number(value.data[1].value) : 0;
    return { start, length };
  }

  // Parse insert_replaced option (single integer or list of integers)
  #parseInsertReplaced(value) {
    if (Type.isInteger(value)) {
      return [Number(value.value)];
    }

    if (Type.isList(value)) {
      return value.data.map(item => {
        if (!Type.isInteger(item)) {
          Interpreter.raiseArgumentError("insert_replaced positions must be integers");
        }
        return Number(item.value);
      });
    }

    return null;
  }

  // Parse tuple option {key, value}
  #parseTupleOption(opt, opts) {
    if (!Type.isTuple(opt) || opt.data.length !== 2) return;

    const [key, value] = opt.data;
    if (!Type.isAtom(key)) return;

    const handlers = {
      scope: () => this.#parseScope(value),
      insert_replaced: () => this.#parseInsertReplaced(value)
    };

    const handler = handlers[key.value];
    if (handler) {
      opts[key.value] = handler();
    }
  }

  // Parse atom option
  #parseAtomOption(opt, opts) {
    const booleanOptions = ['global', 'trim', 'trim_all'];
    if (booleanOptions.includes(opt.value)) {
      opts[opt.value] = true;
    }
  }

  // Parse options for split, replace, match, and matches
  // unused options are ignored
  #parseOptions(options) {
    const opts = {
      global: false,
      trim: false,
      trim_all: false,
      scope: null,
      insert_replaced: null
    };

    if (!Type.isList(options)) return opts;

    for (const opt of options.data) {
      if (Type.isAtom(opt)) {
        this.#parseAtomOption(opt, opts);
      } else {
        this.#parseTupleOption(opt, opts);
      }
    }

    return opts;
  }
}

// Boyer-Moore pattern matching class for single patterns
class BoyerMooreMatcher extends Matcher {
  constructor(pattern) {
    super();
    this.pattern = Matcher.validate_binary(pattern);
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
  #findMatchInternal(subjectBytes, startPos = 0, endPos = null) {
    const patternLength = this.pattern.length;
    const subjectLength = endPos !== null ? endPos : subjectBytes.length;

    if (patternLength === 0 || patternLength > subjectBytes.length) {
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

  // Implement abstract method
  findMatch(subjectBytes, startPos, endPos) {
    return this.#findMatchInternal(subjectBytes, startPos, endPos);
  }

  toTuple() {
    return Type.tuple([
      Type.atom("bm"),
      {
        algorithm: "boyer_moore",
        pattern: this.pattern
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
      Matcher.validate_binary(item)
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
  #findMatchInternal(subjectBytes, startPos = 0, endPos = null, startNode = this.automaton) {
    let currentNode = startNode;
    const searchEnd = endPos !== null ? endPos : subjectBytes.length;

    for (let i = startPos; i < searchEnd; i++) {
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
        const matchStart = i - output.length + 1;

        // Only return match if it starts within the search scope
        if (matchStart >= startPos) {
          return {
            match: {
              start: matchStart,
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
    }

    return null;
  }

  // Implement abstract method
  findMatch(subjectBytes, startPos, endPos) {
    const result = this.#findMatchInternal(subjectBytes, startPos, endPos, this.automaton);
    return result ? result.match : null;
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

  "compile_pattern/1": (pattern) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.toTuple();
  },

  "match/2": (subject, pattern) => {
    return Erlang_Binary["match/3"](subject, pattern, Type.list([]));
  },

  "match/3": (subject, pattern, options) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.match(subject, options);
  },

  "matches/2": (subject, pattern) => {
    return Erlang_Binary["matches/3"](subject, pattern, Type.list([]));
  },

  "matches/3": (subject, pattern, options) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.matches(subject, options);
  },

  "replace/3": (subject, pattern, replacement) => {
    return Erlang_Binary["replace/4"](subject, pattern, replacement, Type.list([]));
  },

  "replace/4": (subject, pattern, replacement, options) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.replace(subject, replacement, options);
  },

  "split/2": (subject, pattern) => {
    return Erlang_Binary["split/3"](subject, pattern, Type.list([]));
  },

  "split/3": (subject, pattern, options) => {
    const patternObj = Matcher.create(pattern);
    return patternObj.split(subject, options);
  }
};

export default Erlang_Binary;