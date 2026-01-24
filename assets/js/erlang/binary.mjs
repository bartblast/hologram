"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang from "./erlang.mjs";
// TODO: consider
// import Erlang_Lists from "./lists.mjs";
import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Binary = {
  // Start _aho_corasick_search/3
  "_aho_corasick_search/3": (subject, rootNode, startIndex) => {
    Bitstring.maybeSetBytesFromText(subject);

    let candidateNode = rootNode;
    let bestMatch = null;

    for (let index = startIndex; index < subject.bytes.length; index++) {
      const byte = subject.bytes[index];

      // Follow failure links until we find a matching transition
      while (candidateNode !== null && !candidateNode.children.has(byte)) {
        candidateNode = candidateNode.failure;
      }

      // Transition to next state or reset to root
      candidateNode = candidateNode
        ? candidateNode.children.get(byte) || rootNode
        : rootNode;

      // Check if current state has any pattern matches
      if (candidateNode.output.length > 0) {
        const matchedPatternLength = candidateNode.output[0].length;
        const matchIndex = index - matchedPatternLength + 1;

        // Update best match if this is first match or a longer match at same/earlier position
        if (
          bestMatch === null ||
          matchIndex < bestMatch.index ||
          (matchIndex === bestMatch.index &&
            matchedPatternLength > bestMatch.length)
        ) {
          bestMatch = {index: matchIndex, length: matchedPatternLength};
        }
      }

      // Check if we should return the current best match
      // Return when we have a match AND current position is past the match end
      // (meaning we can't extend it further with a longer overlapping pattern)
      if (bestMatch !== null && index >= bestMatch.index + bestMatch.length) {
        return bestMatch;
      }
    }

    return bestMatch;
  },
  // End _aho_corasick_search/3
  // Deps: []

  // Start _boyer_moore_search/4
  "_boyer_moore_search/4": (subject, patternBytes, badShift, startIndex) => {
    Bitstring.maybeSetBytesFromText(subject);

    const patternLength = patternBytes.length;
    const patternMaxIndex = patternLength - 1;
    const searchLimit = subject.bytes.length - patternLength;

    for (let index = startIndex; index <= searchLimit; index++) {
      // Compare pattern from right to left
      let patternIndex = patternMaxIndex;

      while (
        patternIndex >= 0 &&
        patternBytes[patternIndex] === subject.bytes[index + patternIndex]
      ) {
        // Full match found
        if (patternIndex === 0) {
          return {index, length: patternLength};
        }

        patternIndex--;
      }

      // No match - use bad character shift to skip ahead
      const currentByte = subject.bytes[index + patternMaxIndex];
      const shiftValue = badShift[currentByte];
      const shift = shiftValue >= 0 ? shiftValue : patternLength;

      if (shift > 0) {
        index += shift - 1; // -1 because loop will increment
      }
    }

    return null;
  },
  // End _boyer_moore_search/4
  // Deps: []

  // Start _parse_search_opts/2
  "_parse_search_opts/2": (opts, argPosition) => {
    const raiseInvalidOptions = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(argPosition, "invalid options"),
      );
    };

    if (!Type.isList(opts) || Type.isImproperList(opts)) {
      raiseInvalidOptions();
    }

    let global = false;
    let trim = false;
    let trimAll = false;
    let scopeStart = 0;
    let scopeLength = -1; // -1 means "until end"

    opts.data.forEach((option) => {
      if (Type.isAtom(option)) {
        if (option.value === "global") {
          global = true;
          return;
        }

        if (option.value === "trim") {
          trim = true;
          return;
        }

        if (option.value === "trim_all") {
          trimAll = true;
          return;
        }

        raiseInvalidOptions();
      }

      const isScopeTuple =
        Type.isTuple(option) &&
        option.data.length === 2 &&
        Type.isAtom(option.data[0]) &&
        option.data[0].value === "scope";

      if (!isScopeTuple) {
        raiseInvalidOptions();
      }

      const scopeData = option.data[1];

      const isValidScope =
        Type.isTuple(scopeData) &&
        scopeData.data.length === 2 &&
        Type.isInteger(scopeData.data[0]) &&
        Type.isInteger(scopeData.data[1]);

      if (!isValidScope) {
        raiseInvalidOptions();
      }

      const startValue = scopeData.data[0].value;
      const lengthValue = scopeData.data[1].value;

      if (startValue < 0n || lengthValue < 0n) {
        raiseInvalidOptions();
      }

      scopeStart = Number(startValue);
      scopeLength = Number(lengthValue);
    });

    return {global, trim, trimAll, scopeStart, scopeLength};
  },
  // End _parse_search_opts/2
  // Deps: []

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
    const raiseInvalidPattern = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a valid pattern"),
      );
    };

    const compileBoyerMoorePattern = (singlePattern) => {
      Bitstring.maybeSetBytesFromText(singlePattern);

      if (singlePattern.bytes.length == 0) {
        raiseInvalidPattern();
      }

      const badShift = {};
      const length = singlePattern.bytes.length - 1;
      const patternBytes = singlePattern.bytes;

      // Seed the badShift object with an initial value of -1 for each byte
      for (let i = 0; i < 256; i++) {
        badShift[i] = -1;
      }

      // Overwrite with the actual value for each byte in the pattern
      singlePattern.bytes.forEach((byte, index) => {
        badShift[byte] = length - index;
      });

      const ref = Erlang["make_ref/0"]();
      const compiledPatternData = {type: "bm", badShift, patternBytes};
      ERTS.binaryPatternRegistry.put(ref, compiledPatternData);

      return Type.tuple([Type.atom("bm"), ref]);
    };

    const compileAhoCorasickPattern = (patterns) => {
      const rootNode = {
        children: new Map(),
        output: [],
        failure: null,
      };

      // Build tries for each pattern
      patterns.data.forEach((p) => {
        Bitstring.maybeSetBytesFromText(p);

        if (p.bytes.length === 0) {
          raiseInvalidPattern();
        }

        let node = rootNode;

        p.bytes.forEach((byte) => {
          if (!node.children.has(byte)) {
            node.children.set(byte, {
              children: new Map(),
              output: [],
              failure: null,
            });
          }

          node = node.children.get(byte);
        });

        node.output.push(p.bytes);
      });

      // Build failure links (where to fall back when a match fails)
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

      const ref = Erlang["make_ref/0"]();
      const compiledPatternData = {type: "ac", rootNode};
      ERTS.binaryPatternRegistry.put(ref, compiledPatternData);

      return Type.tuple([Type.atom("ac"), ref]);
    };

    if (Type.isBinary(pattern)) {
      return compileBoyerMoorePattern(pattern);
    } else if (
      Type.isList(pattern) &&
      pattern.data.length > 0 &&
      pattern.data.every((i) => Type.isBinary(i))
    ) {
      return pattern.data.length == 1
        ? compileBoyerMoorePattern(pattern.data[0])
        : compileAhoCorasickPattern(pattern);
    }

    raiseInvalidPattern();
  },
  // End compile_pattern/1
  // Deps: [:erlang.make_ref/0]

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

  // Start last/1
  "last/1": (subject) => {
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

    return Type.integer(subject.bytes[subject.bytes.length - 1]);
  },
  // End last/1
  // Deps: []

  // Start split/2
  "split/2": (subject, pattern) => {
    return Erlang_Binary["split/3"](subject, pattern, Type.list());
  },
  // End split/2
  // Deps: [:binary.split/3]

  // Start split/3
  "split/3": (subject, pattern, options) => {
    // Helper: Convert byte slice to bitstring (text-based if valid UTF-8)
    const bytesToBitstring = (bytes) => {
      try {
        const decoder = new TextDecoder("utf-8", {fatal: true});
        const text = decoder.decode(bytes);
        return Bitstring.fromText(text);
      } catch {
        return Bitstring.fromBytes(bytes);
      }
    };

    // Helper: Apply trimming options to the split parts
    const applyTrim = (parts) => {
      if (parts.length === 0) {
        return parts;
      }

      if (trimAll) {
        return parts.filter((part) => !Bitstring.isEmpty(part));
      }

      if (!trim) {
        return parts;
      }

      let end = parts.length;
      while (end > 0 && Bitstring.isEmpty(parts[end - 1])) {
        end--;
      }

      return parts.slice(0, end);
    };

    // Validate subject is a binary
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    // Ensure subject bytes are available after validation
    Bitstring.maybeSetBytesFromText(subject);

    const {global, trim, trimAll, scopeStart, scopeLength} = Erlang_Binary[
      "_parse_search_opts/2"
    ](options, 3);

    // Validate scope start is within subject bounds
    if (scopeStart > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    // Validate pattern before compiling (to raise with correct arg position)
    const raiseInvalidPattern = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    };

    const isCompiledPattern = Type.isCompiledPattern(pattern);

    if (!isCompiledPattern) {
      const isValidBinary = Type.isBinary(pattern);

      const isValidList =
        Type.isList(pattern) &&
        pattern.data.length > 0 &&
        pattern.data.every((p) => Type.isBinary(p));

      // Check if pattern is valid before compiling
      if (!isValidBinary && !isValidList) {
        raiseInvalidPattern();
      }

      // Check for empty patterns
      if (isValidBinary) {
        Bitstring.maybeSetBytesFromText(pattern);

        if (pattern.bytes.length === 0) {
          raiseInvalidPattern();
        }
      } else if (isValidList) {
        for (const p of pattern.data) {
          Bitstring.maybeSetBytesFromText(p);

          if (p.bytes.length === 0) {
            raiseInvalidPattern();
          }
        }
      }
    }

    const compiledPattern = isCompiledPattern
      ? pattern
      : Erlang_Binary["compile_pattern/1"](pattern);

    const patternType = compiledPattern.data[0].value;
    const patternRef = compiledPattern.data[1];
    const compiledData = ERTS.binaryPatternRegistry.get(patternRef);

    if (!compiledData || compiledData.type !== patternType) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    const effectiveLength =
      scopeLength === -1 ? subject.bytes.length - scopeStart : scopeLength;

    // Validate scope doesn't extend beyond subject
    if (scopeStart + effectiveLength > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const scopeEnd = scopeStart + effectiveLength;

    // No search range available
    if (scopeStart >= subject.bytes.length || scopeLength === 0) {
      const parts = [bytesToBitstring(subject.bytes)];
      return Type.list(applyTrim(parts));
    }

    const scopedBytes = subject.bytes.slice(scopeStart, scopeEnd);
    const scopedSubject = Bitstring.fromBytes(scopedBytes);

    // Helper: Find next pattern match based on algorithm type inside scoped subject
    const findNextMatch = (startIndex) => {
      if (patternType === "bm") {
        const patternBytes = compiledData.patternBytes;

        if (!patternBytes) {
          Interpreter.raiseArgumentError("is not a valid pattern");
        }

        return Erlang_Binary["_boyer_moore_search/4"](
          scopedSubject,
          patternBytes,
          compiledData.badShift,
          startIndex,
        );
      }

      return Erlang_Binary["_aho_corasick_search/3"](
        scopedSubject,
        compiledData.rootNode,
        startIndex,
      );
    };

    // Main split logic

    const results = [];
    let cursor = 0; // position in full subject where next segment starts
    let searchStart = 0; // position inside scopedSubject
    let foundMatch = true; // track if loop exited naturally vs via break

    while (searchStart < scopedSubject.bytes.length) {
      const match = findNextMatch(searchStart);

      if (match === null) {
        const remaining = bytesToBitstring(subject.bytes.slice(cursor));
        results.push(remaining);
        foundMatch = false; // mark that we broke due to no match
        break;
      }

      const absoluteMatchIndex = scopeStart + match.index;

      const beforeMatch = bytesToBitstring(
        subject.bytes.slice(cursor, absoluteMatchIndex),
      );

      results.push(beforeMatch);
      cursor = absoluteMatchIndex + match.length;
      searchStart = cursor - scopeStart;

      if (!global) {
        const remaining = bytesToBitstring(subject.bytes.slice(cursor));
        results.push(remaining);
        break;
      }
    }

    // Collect any remaining bytes after the last match (for global splits that exited naturally)
    if (global && foundMatch && cursor < subject.bytes.length) {
      const remaining = bytesToBitstring(subject.bytes.slice(cursor));
      results.push(remaining);
    }

    // Add trailing empty when global split ends at subject boundary
    if (global && cursor === subject.bytes.length && results.length > 0) {
      results.push(Bitstring.fromText(""));
    }

    if (results.length === 0) {
      results.push(bytesToBitstring(subject.bytes));
    }

    const trimmedResults = applyTrim(results);

    return Type.list(trimmedResults);
  },
  // End split/3
  // Deps: [:binary._aho_corasick_search/3, :binary._boyer_moore_search/4, :binary._parse_search_opts/2, :binary.compile_pattern/1]
};

export default Erlang_Binary;
