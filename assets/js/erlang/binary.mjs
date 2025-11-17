"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Binary = {
  // Start at/2
  "at/2": (binary, index) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(index)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;
    const indexNum = Number(index.value);

    if (indexNum < 0 || indexNum >= bytes.length) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.integer(bytes[indexNum]);
  },
  // End at/2
  // Deps: []

  // Start compile_pattern/1
  "compile_pattern/1": (pattern) => {
    // Normalize pattern to array of binaries
    let patterns;

    if (Type.isBinary(pattern)) {
      patterns = [pattern];
    } else if (Type.isList(pattern)) {
      if (!pattern.data.every((p) => Type.isBinary(p))) {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(1, "not a binary or list of binaries"),
        );
      }
      patterns = pattern.data;
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or list of binaries"),
      );
    }

    // Convert patterns to byte arrays for efficient searching
    const compiledPatterns = patterns.map((p) => {
      Bitstring.maybeSetBytesFromText(p);
      return {
        bytes: p.bytes,
        length: p.bytes.length,
      };
    });

    // Return opaque compiled pattern structure
    // In real Erlang this is an opaque type, we'll use a special marker
    return Type.tuple([
      Type.atom("binary_compiled_pattern"),
      Type.list(compiledPatterns.map((cp) => {
        return Type.tuple([
          Type.bitstring(cp.bytes, 0),
          Type.integer(cp.length),
        ]);
      })),
    ]);
  },
  // End compile_pattern/1
  // Deps: []

  // Start copy/2
  "copy/2": (binary, count) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(count)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    const countNum = Number(count.value);

    if (countNum < 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    if (countNum === 0) {
      return Type.bitstring(new Uint8Array(0), 0);
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;
    const totalLength = bytes.length * countNum;
    const result = new Uint8Array(totalLength);

    for (let i = 0; i < countNum; i++) {
      result.set(bytes, i * bytes.length);
    }

    return Type.bitstring(result, 0);
  },
  // End copy/2
  // Deps: []

  // Start first/1
  "first/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;

    if (bytes.length === 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.integer(bytes[0]);
  },
  // End first/1
  // Deps: []

  // Start last/1
  "last/1": (binary) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;

    if (bytes.length === 0) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Type.integer(bytes[bytes.length - 1]);
  },
  // End last/1
  // Deps: []

  // Start match/2
  "match/2": (subject, pattern) => {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    // Pattern can be a binary or compiled pattern
    let patterns;

    if (Type.isBinary(pattern)) {
      patterns = [{bytes: null, binary: pattern}];
    } else if (Type.isTuple(pattern) && pattern.data.length === 2) {
      const marker = pattern.data[0];
      if (Type.isAtom(marker) && marker.value === "binary_compiled_pattern") {
        const patternList = pattern.data[1];
        patterns = patternList.data.map((p) => ({
          bytes: null,
          binary: p.data[0],
        }));
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);
    const subjectBytes = subject.bytes;

    // Search for first match of any pattern
    for (const patternInfo of patterns) {
      Bitstring.maybeSetBytesFromText(patternInfo.binary);
      const patternBytes = patternInfo.binary.bytes;

      for (let i = 0; i <= subjectBytes.length - patternBytes.length; i++) {
        let match = true;
        for (let j = 0; j < patternBytes.length; j++) {
          if (subjectBytes[i + j] !== patternBytes[j]) {
            match = false;
            break;
          }
        }

        if (match) {
          return Type.tuple([
            Type.integer(i),
            Type.integer(patternBytes.length),
          ]);
        }
      }
    }

    return Type.atom("nomatch");
  },
  // End match/2
  // Deps: []

  // Start matches/2
  "matches/2": (subject, pattern) => {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    // Pattern can be a binary or compiled pattern
    let patterns;

    if (Type.isBinary(pattern)) {
      patterns = [{bytes: null, binary: pattern}];
    } else if (Type.isTuple(pattern) && pattern.data.length === 2) {
      const marker = pattern.data[0];
      if (Type.isAtom(marker) && marker.value === "binary_compiled_pattern") {
        const patternList = pattern.data[1];
        patterns = patternList.data.map((p) => ({
          bytes: null,
          binary: p.data[0],
        }));
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);
    const subjectBytes = subject.bytes;
    const results = [];

    // Search for all matches of any pattern
    for (const patternInfo of patterns) {
      Bitstring.maybeSetBytesFromText(patternInfo.binary);
      const patternBytes = patternInfo.binary.bytes;

      for (let i = 0; i <= subjectBytes.length - patternBytes.length; i++) {
        let match = true;
        for (let j = 0; j < patternBytes.length; j++) {
          if (subjectBytes[i + j] !== patternBytes[j]) {
            match = false;
            break;
          }
        }

        if (match) {
          results.push(
            Type.tuple([Type.integer(i), Type.integer(patternBytes.length)]),
          );
        }
      }
    }

    return Type.list(results);
  },
  // End matches/2
  // Deps: []

  // Start replace/4
  "replace/4": (subject, pattern, replacement, options) => {
    if (!Type.isBinary(subject)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isBinary(replacement)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a binary"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(4, "not a list"),
      );
    }

    // Parse options
    let scope = null; // null means replace all
    let insert_replaced = null;
    let insert_value = null;

    for (const option of options.data) {
      if (Type.isAtom(option) && option.value === "global") {
        scope = "all";
      } else if (Type.isTuple(option) && option.data.length === 2) {
        const key = option.data[0];
        const value = option.data[1];

        if (Type.isAtom(key) && key.value === "scope") {
          if (Type.isTuple(value) && value.data.length === 2) {
            const start = value.data[0];
            const length = value.data[1];
            if (Type.isInteger(start) && Type.isInteger(length)) {
              scope = {
                start: Number(start.value),
                length: Number(length.value),
              };
            }
          }
        } else if (Type.isAtom(key) && key.value === "insert_replaced") {
          if (Type.isInteger(value)) {
            insert_replaced = Number(value.value);
          }
        }
      }
    }

    // Get pattern bytes
    let patterns;
    if (Type.isBinary(pattern)) {
      patterns = [{bytes: null, binary: pattern}];
    } else if (Type.isTuple(pattern) && pattern.data.length === 2) {
      const marker = pattern.data[0];
      if (Type.isAtom(marker) && marker.value === "binary_compiled_pattern") {
        const patternList = pattern.data[1];
        patterns = patternList.data.map((p) => ({
          bytes: null,
          binary: p.data[0],
        }));
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    Bitstring.maybeSetBytesFromText(subject);
    Bitstring.maybeSetBytesFromText(replacement);
    const subjectBytes = subject.bytes;
    const replacementBytes = replacement.bytes;

    // Find all matches
    const matches = [];
    for (const patternInfo of patterns) {
      Bitstring.maybeSetBytesFromText(patternInfo.binary);
      const patternBytes = patternInfo.binary.bytes;

      for (let i = 0; i <= subjectBytes.length - patternBytes.length; i++) {
        let match = true;
        for (let j = 0; j < patternBytes.length; j++) {
          if (subjectBytes[i + j] !== patternBytes[j]) {
            match = false;
            break;
          }
        }

        if (match) {
          matches.push({start: i, length: patternBytes.length});
          // Skip overlapping matches
          i += patternBytes.length - 1;
        }
      }
    }

    // Apply scope filter if specified
    let filteredMatches = matches;
    if (scope !== null && scope !== "all") {
      filteredMatches = matches.filter(
        (m) =>
          m.start >= scope.start && m.start < scope.start + scope.length,
      );
    }

    // Build result binary
    const resultParts = [];
    let lastPos = 0;

    for (const match of filteredMatches) {
      // Add bytes before match
      if (match.start > lastPos) {
        resultParts.push(subjectBytes.slice(lastPos, match.start));
      }

      // Add replacement (with insert_replaced logic if specified)
      if (insert_replaced !== null) {
        const matchedBytes = subjectBytes.slice(
          match.start,
          match.start + match.length,
        );
        if (insert_replaced === 0) {
          resultParts.push(matchedBytes);
          resultParts.push(replacementBytes);
        } else {
          resultParts.push(replacementBytes);
          resultParts.push(matchedBytes);
        }
      } else {
        resultParts.push(replacementBytes);
      }

      lastPos = match.start + match.length;
    }

    // Add remaining bytes
    if (lastPos < subjectBytes.length) {
      resultParts.push(subjectBytes.slice(lastPos));
    }

    // Concatenate all parts
    const totalLength = resultParts.reduce((sum, part) => sum + part.length, 0);
    const resultBytes = new Uint8Array(totalLength);
    let offset = 0;
    for (const part of resultParts) {
      resultBytes.set(part, offset);
      offset += part.length;
    }

    return Type.bitstring(resultBytes, 0);
  },
  // End replace/4
  // Deps: []

  // Start part/2
  "part/2": (binary, posLen) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isTuple(posLen) || posLen.data.length !== 2) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid {Pos, Len} tuple"),
      );
    }

    const pos = posLen.data[0];
    const len = posLen.data[1];

    if (!Type.isInteger(pos) || !Type.isInteger(len)) {
      Interpreter.raiseArgumentError("argument error");
    }

    return Erlang_Binary["part/3"](binary, pos, len);
  },
  // End part/2
  // Deps: [:binary.part/3]

  // Start part/3
  "part/3": (binary, pos, len) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isInteger(pos)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an integer"),
      );
    }

    if (!Type.isInteger(len)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not an integer"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;
    const posNum = Number(pos.value);
    const lenNum = Number(len.value);

    // Negative position means count from end
    const actualPos = posNum < 0 ? bytes.length + posNum : posNum;

    if (actualPos < 0 || actualPos > bytes.length) {
      Interpreter.raiseArgumentError("argument error");
    }

    if (lenNum < 0 || actualPos + lenNum > bytes.length) {
      Interpreter.raiseArgumentError("argument error");
    }

    const result = bytes.slice(actualPos, actualPos + lenNum);
    return Type.bitstring(result, 0);
  },
  // End part/3
  // Deps: []

  // Start split/2
  "split/2": (binary, pattern) => {
    return Erlang_Binary["split/3"](binary, pattern, Type.list([]));
  },
  // End split/2
  // Deps: [:binary.split/3]

  // Start split/3
  "split/3": (binary, pattern, options) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Parse options
    let global = false;
    let trim = false;
    let trim_all = false;

    for (const option of options.data) {
      if (Type.isAtom(option)) {
        if (option.value === "global") {
          global = true;
        } else if (option.value === "trim") {
          trim = true;
        } else if (option.value === "trim_all") {
          trim_all = true;
        }
      }
    }

    // Get pattern bytes
    let patterns;
    if (Type.isBinary(pattern)) {
      patterns = [{bytes: null, binary: pattern}];
    } else if (Type.isTuple(pattern) && pattern.data.length === 2) {
      const marker = pattern.data[0];
      if (Type.isAtom(marker) && marker.value === "binary_compiled_pattern") {
        const patternList = pattern.data[1];
        patterns = patternList.data.map((p) => ({
          bytes: null,
          binary: p.data[0],
        }));
      } else {
        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
        );
      }
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid pattern"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;

    // Find first (or all if global) match
    let splitPos = -1;
    let splitLen = 0;

    const matches = [];
    for (const patternInfo of patterns) {
      Bitstring.maybeSetBytesFromText(patternInfo.binary);
      const patternBytes = patternInfo.binary.bytes;

      for (let i = 0; i <= bytes.length - patternBytes.length; i++) {
        let match = true;
        for (let j = 0; j < patternBytes.length; j++) {
          if (bytes[i + j] !== patternBytes[j]) {
            match = false;
            break;
          }
        }

        if (match) {
          if (!global) {
            // Just find first match
            splitPos = i;
            splitLen = patternBytes.length;
            break;
          } else {
            matches.push({pos: i, len: patternBytes.length});
            i += patternBytes.length - 1; // Skip overlapping
          }
        }
      }

      if (splitPos >= 0 && !global) break;
    }

    if (!global) {
      // Split once
      if (splitPos < 0) {
        return Type.list([binary]);
      }

      const part1 = bytes.slice(0, splitPos);
      const part2 = bytes.slice(splitPos + splitLen);

      return Type.list([
        Type.bitstring(part1, 0),
        Type.bitstring(part2, 0),
      ]);
    } else {
      // Split multiple times
      if (matches.length === 0) {
        return Type.list([binary]);
      }

      const parts = [];
      let lastPos = 0;

      for (const match of matches) {
        const part = bytes.slice(lastPos, match.pos);
        parts.push(Type.bitstring(part, 0));
        lastPos = match.pos + match.len;
      }

      // Add final part
      const finalPart = bytes.slice(lastPos);
      parts.push(Type.bitstring(finalPart, 0));

      // Apply trim options
      if (trim_all) {
        return Type.list(parts.filter((p) => p.bytes.length > 0));
      } else if (trim) {
        // Remove leading/trailing empty parts
        while (parts.length > 0 && parts[0].bytes.length === 0) {
          parts.shift();
        }
        while (parts.length > 0 && parts[parts.length - 1].bytes.length === 0) {
          parts.pop();
        }
      }

      return Type.list(parts);
    }
  },
  // End split/3
  // Deps: []

  // Start decode_unsigned/1
  "decode_unsigned/1": (binary) => {
    return Erlang_Binary["decode_unsigned/2"](binary, Type.atom("big"));
  },
  // End decode_unsigned/1
  // Deps: [:binary.decode_unsigned/2]

  // Start decode_unsigned/2
  "decode_unsigned/2": (binary, endianness) => {
    if (!Type.isBinary(binary)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary"),
      );
    }

    if (!Type.isAtom(endianness)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    Bitstring.maybeSetBytesFromText(binary);
    const bytes = binary.bytes;

    if (bytes.length === 0) {
      return Type.integer(0);
    }

    let result = 0n;
    const isBig = endianness.value === "big";

    if (isBig) {
      // Big endian: most significant byte first
      for (let i = 0; i < bytes.length; i++) {
        result = (result << 8n) | BigInt(bytes[i]);
      }
    } else {
      // Little endian: least significant byte first
      for (let i = bytes.length - 1; i >= 0; i--) {
        result = (result << 8n) | BigInt(bytes[i]);
      }
    }

    return Type.integer(result);
  },
  // End decode_unsigned/2
  // Deps: []
};

export default Erlang_Binary;
