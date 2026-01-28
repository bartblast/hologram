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
        // Check all matches at this position and keep the longest one
        for (const matchedPattern of candidateNode.output) {
          const matchedPatternLength = matchedPattern.length;
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
      }

      // Check if we should return the current best match
      // Return when we have a match AND we're past the match end AND we're not matching any pattern
      // (candidateNode == rootNode means we're not in the middle of matching)
      if (
        bestMatch !== null &&
        index >= bestMatch.index + bestMatch.length &&
        candidateNode === rootNode
      ) {
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
    let scopeLength = null; // null means "until end"

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

      if (startValue < 0n) {
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

  // Start match/2
  "match/2": (subject, pattern) => {
    return Erlang_Binary["match/3"](subject, pattern, Type.list());
  },
  // End match/2
  // Deps: [:binary.match/3]

  // Start match/3
  "match/3": (subject, pattern, options) => {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    // Ensure subject bytes are available after validation
    Bitstring.maybeSetBytesFromText(subject);

    // Parse options and reject unsupported flags for match/3
    const {global, trim, trimAll, scopeStart, scopeLength} = Erlang_Binary[
      "_parse_search_opts/2"
    ](options, 3);

    // match/3 only supports :scope; reject :global, :trim, and :trim_all
    // Validate scope start is within subject bounds
    if (global || trim || trimAll || scopeStart > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    // Validate that if scopeLength is specified, scopeStart + scopeLength >= 0
    if (scopeLength !== null && scopeStart + scopeLength < 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const effectiveLength =
      scopeLength === null ? subject.bytes.length - scopeStart : scopeLength;

    // Validate scope doesn't extend beyond subject
    if (scopeStart + effectiveLength > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const scopeEnd = scopeStart + effectiveLength;

    // For negative scopeLength, ensure slice bounds are in correct order
    const actualStart = Math.min(scopeStart, scopeEnd);
    const actualEnd = Math.max(scopeStart, scopeEnd);

    // Validate pattern before checking scope length - pattern errors take priority
    const isCompiledPattern = Type.isCompiledPattern(pattern);

    let compiledPattern;

    try {
      compiledPattern = isCompiledPattern
        ? pattern
        : Erlang_Binary["compile_pattern/1"](pattern);
    } catch (error) {
      // Re-raise pattern compilation errors with correct argument position
      if (error.struct) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }

      throw error;
    }

    const patternType = compiledPattern.data[0].value;
    const patternRef = compiledPattern.data[1];
    const compiledData = ERTS.binaryPatternRegistry.get(patternRef);

    if (!compiledData || compiledData.type !== patternType) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    // After pattern validation passes, check if search range is available
    if (scopeLength === 0) {
      return Type.atom("nomatch");
    }

    const scopedBytes = subject.bytes.slice(actualStart, actualEnd);
    const scopedSubject = Bitstring.fromBytes(scopedBytes);

    // Find first pattern match based on algorithm type
    let match = null;

    if (patternType === "bm") {
      const patternBytes = compiledData.patternBytes;

      if (!patternBytes) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }

      match = Erlang_Binary["_boyer_moore_search/4"](
        scopedSubject,
        patternBytes,
        compiledData.badShift,
        0,
      );
    } else {
      match = Erlang_Binary["_aho_corasick_search/3"](
        scopedSubject,
        compiledData.rootNode,
        0,
      );
    }

    if (match === null) {
      return Type.atom("nomatch");
    }

    // Convert match position from scoped to absolute
    const absolutePos = actualStart + match.index;

    return Type.tuple([Type.integer(absolutePos), Type.integer(match.length)]);
  },
  // End match/3
  // Deps: [:binary._aho_corasick_search/3, :binary._boyer_moore_search/4, :binary._parse_search_opts/2, :binary.compile_pattern/1]

  // Start matches/2
  "matches/2": (subject, pattern) => {
    return Erlang_Binary["matches/3"](subject, pattern, Type.list());
  },
  // End matches/2
  // Deps: [:binary.matches/3]

  // Start matches/3
  "matches/3": (subject, pattern, options) => {
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    Bitstring.maybeSetBytesFromText(subject);

    const {global, trim, trimAll, scopeStart, scopeLength} = Erlang_Binary[
      "_parse_search_opts/2"
    ](options, 3);

    if (global || trim || trimAll || scopeStart > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    if (scopeLength !== null && scopeStart + scopeLength < 0) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const isCompiledPattern = Type.isCompiledPattern(pattern);

    let compiledPattern;

    try {
      compiledPattern = isCompiledPattern
        ? pattern
        : Erlang_Binary["compile_pattern/1"](pattern);
    } catch (error) {
      if (error.struct) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }

      throw error;
    }

    const patternType = compiledPattern.data[0].value;
    const patternRef = compiledPattern.data[1];
    const compiledData = ERTS.binaryPatternRegistry.get(patternRef);

    if (!compiledData || compiledData.type !== patternType) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    const effectiveLength =
      scopeLength === null ? subject.bytes.length - scopeStart : scopeLength;

    if (scopeStart + effectiveLength > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const scopeEnd = scopeStart + effectiveLength;
    const searchStart = Math.min(scopeStart, scopeEnd);
    const searchEnd = Math.max(scopeStart, scopeEnd);

    if (scopeLength === 0 || searchStart >= subject.bytes.length) {
      return Type.list();
    }

    const results = [];
    let currentStart = searchStart;

    while (currentStart < searchEnd) {
      const remainingLength = searchEnd - currentStart;

      const matchOptions = Type.list([
        Type.tuple([
          Type.atom("scope"),
          Type.tuple([
            Type.integer(currentStart),
            Type.integer(remainingLength),
          ]),
        ]),
      ]);

      const matchResult = Erlang_Binary["match/3"](
        subject,
        compiledPattern,
        matchOptions,
      );

      if (Type.isAtom(matchResult) && matchResult.value === "nomatch") {
        break;
      }

      results.push(matchResult);

      const matchPos = Number(matchResult.data[0].value);
      const matchLength = Number(matchResult.data[1].value);

      currentStart = matchPos + matchLength;
    }

    return Type.list(results);
  },
  // End matches/3
  // Deps: [:binary._parse_search_opts/2, :binary.compile_pattern/1, :binary.match/3]

  // Start replace/3
  "replace/3": (subject, pattern, replacement) => {
    return Erlang_Binary["replace/4"](
      subject,
      pattern,
      replacement,
      Type.list(),
    );
  },
  // End replace/3
  // Deps: [:binary.replace/4]

  // Start replace/4
  "replace/4": (subject, pattern, replacement, options) => {
    // Helpers (alphabetical): describe steps, flatten branching
    const utf8Decoder = new TextDecoder("utf-8", {fatal: true});

    const bytesToBitstring = (bytes) => {
      try {
        const text = utf8Decoder.decode(bytes);
        return Bitstring.fromText(text);
      } catch {
        return Bitstring.fromBytes(bytes);
      }
    };

    const compilePatternOrRaise = (pat, argPos) => {
      const isCompiled = Type.isCompiledPattern(pat);
      try {
        return isCompiled ? pat : Erlang_Binary["compile_pattern/1"](pat);
      } catch (error) {
        if (error.struct) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(argPos, "not a valid pattern"),
          );
        }
        throw error;
      }
    };

    const computeScopeBounds = (subjectBin, start, length, argPos) => {
      if (start > subjectBin.bytes.length) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(argPos, "invalid options"),
        );
      }

      if (length !== null && start + length < 0) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(argPos, "invalid options"),
        );
      }

      const effectiveLength =
        length === null ? subjectBin.bytes.length - start : length;

      if (start + effectiveLength > subjectBin.bytes.length) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(argPos, "invalid options"),
        );
      }

      const scopeEnd = start + effectiveLength;
      return {
        actualStart: Math.min(start, scopeEnd),
        actualEnd: Math.max(start, scopeEnd),
        effectiveLength,
      };
    };

    const getCompiledData = (compiledPat) => {
      const type = compiledPat.data[0].value;
      const ref = compiledPat.data[1];
      const data = ERTS.binaryPatternRegistry.get(ref);
      if (!data || data.type !== type) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }
      return {type, data};
    };

    const insertReplacedAtPositions = (
      replacementBin,
      matchedBin,
      insertPositions,
    ) => {
      const positions = Type.isList(insertPositions)
        ? insertPositions.data.map((p) => Number(p.value))
        : [Number(insertPositions.value)];

      Bitstring.maybeSetBytesFromText(replacementBin);
      Bitstring.maybeSetBytesFromText(matchedBin);

      const repBytes = replacementBin.bytes;
      const replacementLength = repBytes.length;

      for (const pos of positions) {
        if (pos > replacementLength) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(4, "invalid options"),
          );
        }
      }

      positions.sort((a, b) => b - a);
      let resultBytes = [...repBytes];
      for (const pos of positions) {
        resultBytes.splice(pos, 0, ...matchedBin.bytes);
      }

      try {
        const decoder = new TextDecoder("utf-8", {fatal: true});
        const text = decoder.decode(new Uint8Array(resultBytes));
        return Bitstring.fromText(text);
      } catch {
        return Bitstring.fromBytes(new Uint8Array(resultBytes));
      }
    };

    const interleaveReplacement = (partsList, replacementBin) => {
      Bitstring.maybeSetBytesFromText(replacementBin);
      const items = [];
      const len = partsList.data.length;
      for (let i = 0; i < len; i++) {
        items.push(partsList.data[i]);
        if (i < len - 1) items.push(replacementBin);
      }
      return Erlang["iolist_to_binary/1"](Type.list(items));
    };

    const parseReplaceOpts = (opts, argPosition) => {
      const raiseInvalidOptions = () => {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(argPosition, "invalid options"),
        );
      };

      if (!Type.isList(opts) || Type.isImproperList(opts)) {
        raiseInvalidOptions();
      }

      let global = false;
      let scopeStart = 0;
      let scopeLength = null; // null means "until end"
      let insertReplaced = null;

      opts.data.forEach((option) => {
        if (Type.isAtom(option)) {
          if (option.value === "global") {
            global = true;
            return;
          }
          raiseInvalidOptions();
        }

        const isScopeTuple =
          Type.isTuple(option) &&
          option.data.length === 2 &&
          Type.isAtom(option.data[0]) &&
          option.data[0].value === "scope";

        if (isScopeTuple) {
          const scopeData = option.data[1];
          const isValidScope =
            Type.isTuple(scopeData) &&
            scopeData.data.length === 2 &&
            Type.isInteger(scopeData.data[0]) &&
            Type.isInteger(scopeData.data[1]);
          if (!isValidScope) raiseInvalidOptions();

          const startValue = scopeData.data[0].value;
          const lengthValue = scopeData.data[1].value;
          if (startValue < 0n) raiseInvalidOptions();

          scopeStart = Number(startValue);
          scopeLength = Number(lengthValue);
          return;
        }

        const isInsertTuple =
          Type.isTuple(option) &&
          option.data.length === 2 &&
          Type.isAtom(option.data[0]) &&
          option.data[0].value === "insert_replaced";

        if (isInsertTuple) {
          const insertData = option.data[1];
          if (Type.isInteger(insertData)) {
            if (insertData.value < 0n) raiseInvalidOptions();
            insertReplaced = insertData;
          } else if (Type.isList(insertData)) {
            // Reject improper lists to match top-level options validation
            if (Type.isImproperList(insertData)) raiseInvalidOptions();
            const allIntegers = insertData.data.every((item) =>
              Type.isInteger(item),
            );
            if (!allIntegers) raiseInvalidOptions();
            const hasNegative = insertData.data.some((item) => item.value < 0n);
            if (hasNegative) raiseInvalidOptions();
            insertReplaced = insertData;
          } else {
            raiseInvalidOptions();
          }
          return;
        }

        raiseInvalidOptions();
      });

      return {global, scopeStart, scopeLength, insertReplaced};
    };

    // Helper closes over isReplacementFunction and replacement for clarity
    const buildReplacementBytes = (matchedBitstring, insertPositionsOpt) => {
      if (isReplacementFunction) {
        const replacementResult = Interpreter.callAnonymousFunction(
          replacement,
          [matchedBitstring],
        );

        if (!Type.isBinary(replacementResult)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(4, "invalid options"),
          );
        }

        Bitstring.maybeSetBytesFromText(replacementResult);
        return replacementResult.bytes;
      }

      if (insertPositionsOpt !== null) {
        const withInserted = insertReplacedAtPositions(
          replacement,
          matchedBitstring,
          insertPositionsOpt,
        );

        Bitstring.maybeSetBytesFromText(withInserted);
        return withInserted.bytes;
      }

      Bitstring.maybeSetBytesFromText(replacement);
      return replacement.bytes;
    };

    // Validate subject is a binary
    if (!Type.isBinary(subject)) {
      const msg = Type.isBitstring(subject)
        ? "is a bitstring (expected a binary)"
        : "not a binary";

      Interpreter.raiseArgumentError(Interpreter.buildArgumentErrorMsg(1, msg));
    }

    // Ensure subject bytes are available
    Bitstring.maybeSetBytesFromText(subject);

    // Validate replacement is either binary or function
    const isReplacementBinary = Type.isBinary(replacement);
    const isReplacementFunction = Type.isAnonymousFunction(replacement);

    if (!isReplacementBinary && !isReplacementFunction) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a valid replacement"),
      );
    }

    // Parse options
    const {
      global,
      scopeStart,
      scopeLength,
      insertReplaced: insertPositionsOpt,
    } = parseReplaceOpts(options, 4);

    const {actualStart, actualEnd, effectiveLength} = computeScopeBounds(
      subject,
      scopeStart,
      scopeLength,
      4,
    );

    // Validate pattern before checking scope length - pattern errors take priority
    const compiledPattern = compilePatternOrRaise(pattern, 2);
    const {type: patternType, data: compiledData} =
      getCompiledData(compiledPattern);

    // After pattern validation passes, check if search range is available
    if (scopeLength === 0) {
      return subject;
    }

    // Fast-path: static binary replacement without insert_replaced
    if (!isReplacementFunction && insertPositionsOpt === null) {
      const splitOpts = [];
      if (global) splitOpts.push(Type.atom("global"));
      if (effectiveLength !== subject.bytes.length || scopeStart !== 0) {
        splitOpts.push(
          Type.tuple([
            Type.atom("scope"),
            Type.tuple([
              Type.integer(actualStart),
              Type.integer(actualEnd - actualStart),
            ]),
          ]),
        );
      }
      const parts = Erlang_Binary["split/3"](
        subject,
        compiledPattern,
        Type.list(splitOpts),
      );
      return interleaveReplacement(parts, replacement);
    }

    // Build replacement segments
    const resultSegments = [];

    // Add the part before the scope (if any)
    if (actualStart > 0) {
      resultSegments.push(subject.bytes.subarray(0, actualStart));
    }

    // Build replacement segments within the scope
    const scopedSegments = [];
    const scopedBytes = subject.bytes.subarray(actualStart, actualEnd);
    const scopedSubject = Bitstring.fromBytes(scopedBytes);

    let cursor = 0; // position within scoped bytes
    let foundAny = false;

    while (cursor < scopedBytes.length) {
      let match;

      if (patternType === "bm") {
        match = Erlang_Binary["_boyer_moore_search/4"](
          scopedSubject,
          compiledData.patternBytes,
          compiledData.badShift,
          cursor,
        );
      } else {
        match = Erlang_Binary["_aho_corasick_search/3"](
          scopedSubject,
          compiledData.rootNode,
          cursor,
        );
      }

      if (match === null) {
        break;
      }

      const matchStartScoped = match.index;
      const matchLength = match.length;
      const absMatchStart = actualStart + matchStartScoped;

      foundAny = true;

      if (matchStartScoped > cursor) {
        scopedSegments.push(
          subject.bytes.subarray(actualStart + cursor, absMatchStart),
        );
      }

      const matchedBytes = subject.bytes.subarray(
        absMatchStart,
        absMatchStart + matchLength,
      );
      const matchedBitstring = bytesToBitstring(matchedBytes);
      Bitstring.maybeSetBytesFromText(matchedBitstring);

      const replacementBytes = buildReplacementBytes(
        matchedBitstring,
        insertPositionsOpt,
      );

      scopedSegments.push(replacementBytes);

      cursor = matchStartScoped + matchLength;

      if (!global) {
        if (cursor < scopedBytes.length) {
          scopedSegments.push(
            subject.bytes.subarray(actualStart + cursor, actualEnd),
          );
        }

        break;
      }
    }

    if (foundAny && global && cursor < scopedBytes.length) {
      scopedSegments.push(
        subject.bytes.subarray(actualStart + cursor, actualEnd),
      );
    } else if (!foundAny) {
      scopedSegments.push(subject.bytes.subarray(actualStart, actualEnd));
    }

    // Add the scoped segments to result
    for (const segment of scopedSegments) {
      resultSegments.push(segment);
    }

    // Add the part after the scope (if any)
    if (actualEnd < subject.bytes.length) {
      resultSegments.push(subject.bytes.subarray(actualEnd));
    }

    // Build final result from all segments
    const resultBytes = new Uint8Array(
      resultSegments.reduce((sum, seg) => sum + seg.length, 0),
    );

    let offset = 0;

    for (const segment of resultSegments) {
      resultBytes.set(segment, offset);
      offset += segment.length;
    }

    const result = bytesToBitstring(resultBytes);
    Bitstring.maybeSetBytesFromText(result);
    return result;
  },
  // End replace/4
  // Deps: [:erlang.iolist_to_binary/1, :binary.compile_pattern/1, :binary.match/3, :binary.split/3]

  // Start split/2
  "split/2": (subject, pattern) => {
    return Erlang_Binary["split/3"](subject, pattern, Type.list());
  },
  // End split/2
  // Deps: [:binary.split/3]

  // Start split/3
  "split/3": (subject, pattern, options) => {
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

    // Validate that if scopeLength is specified, scopeStart + scopeLength >= 0
    if (scopeLength !== null && scopeStart + scopeLength < 0) {
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

    // Pre-compile pattern once before loop to avoid recompilation on each match
    const compiledPattern = isCompiledPattern
      ? pattern
      : Erlang_Binary["compile_pattern/1"](pattern);

    const effectiveLength =
      scopeLength === null ? subject.bytes.length - scopeStart : scopeLength;

    // Validate scope doesn't extend beyond subject
    if (scopeStart + effectiveLength > subject.bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "invalid options"),
      );
    }

    const scopeEnd = scopeStart + effectiveLength;

    // For negative scopeLength, ensure slice bounds are in correct order
    const actualStart = Math.min(scopeStart, scopeEnd);
    const actualEnd = Math.max(scopeStart, scopeEnd);

    // No search range available - return unsplit subject
    if (actualStart >= subject.bytes.length) {
      const parts = [bytesToBitstring(subject.bytes)];
      return Type.list(applyTrim(parts));
    }

    // Main split logic using match/3

    const results = [];
    let cursor = 0; // position in full subject where next segment starts
    let searchPos = actualStart; // current search position
    let foundMatch = true; // track if loop exited naturally vs via break

    while (searchPos < actualEnd) {
      const remainingLength = actualEnd - searchPos;

      const matchOptions = Type.list([
        Type.tuple([
          Type.atom("scope"),
          Type.tuple([Type.integer(searchPos), Type.integer(remainingLength)]),
        ]),
      ]);

      // Use match/3 to find next occurrence with pre-compiled pattern
      const matchResult = Erlang_Binary["match/3"](
        subject,
        compiledPattern,
        matchOptions,
      );

      // No more matches found
      if (Type.isAtom(matchResult) && matchResult.value === "nomatch") {
        const remaining =
          cursor < subject.bytes.length
            ? bytesToBitstring(subject.bytes.slice(cursor))
            : Bitstring.fromText("");

        results.push(remaining);
        foundMatch = false;

        break;
      }

      // Extract match position and length
      const matchPos = matchResult.data[0].value;
      const matchLen = matchResult.data[1].value;
      const matchStart = Number(matchPos);
      const matchLength = Number(matchLen);

      // Add part before match (if any)
      if (matchStart > cursor) {
        const beforeMatch = bytesToBitstring(
          subject.bytes.slice(cursor, matchStart),
        );

        results.push(beforeMatch);
      } else if (matchStart === cursor) {
        // Empty part before match
        results.push(Bitstring.fromText(""));
      }

      // Update cursor to position after match
      cursor = matchStart + matchLength;
      searchPos = cursor;

      if (!global) {
        // For non-global split, append remaining and stop
        const remaining =
          cursor < subject.bytes.length
            ? bytesToBitstring(subject.bytes.slice(cursor))
            : Bitstring.fromText("");

        results.push(remaining);
        foundMatch = false;

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
  // Deps: [:binary._parse_search_opts/2, :binary.compile_pattern/1, :binary.match/3]
};

export default Erlang_Binary;
