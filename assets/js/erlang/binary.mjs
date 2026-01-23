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
    const compileBoyerMoorePattern = (singlePattern) => {
      Bitstring.maybeSetBytesFromText(singlePattern);

      if (singlePattern.bytes.length == 0) {
        Interpreter.raiseArgumentError("is not a valid pattern");
      }

      const badShift = {};
      const length = singlePattern.bytes.length - 1;

      // Seed the badShift object with an initial value of -1 for each byte
      for (let i = 0; i < 256; i++) {
        badShift[i] = -1;
      }

      // Overwrite with the actual value for each byte in the pattern
      singlePattern.bytes.forEach((byte, index) => {
        badShift[byte] = length - index;
      });

      const ref = Erlang["make_ref/0"]();
      const compiledPatternData = {type: "bm", badShift};
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
          Interpreter.raiseArgumentError("is not a valid pattern");
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

    Interpreter.raiseArgumentError("is not a valid pattern");
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

  // TODO: consider
  // // Start _aho_corasick_search/3
  // "_aho_corasick_search/3": (subject, patterns, options) => {
  //   const {start, length} = Erlang_Binary["_parse_search_opts/1"](options);
  //   const compiledPatternData = ERTS.binaryPatternRegistry.get(patterns);

  //   Bitstring.maybeSetBytesFromText(subject);
  //   const startIndex = Math.max(start, 0);
  //   const maxIndex = Math.max(start + length, subject.bytes.length);

  //   const rootNode = compiledPatternData.rootNode;
  //   let candidateNode = rootNode;

  //   for (let index = startIndex; index < maxIndex; index++) {
  //     const byte = subject.bytes[index];

  //     while (candidateNode !== null && !candidateNode.children.has(byte)) {
  //       candidateNode = candidateNode.failure;
  //     }

  //     // next node, or back to root
  //     candidateNode = candidateNode
  //       ? candidateNode.children.get(byte) || rootNode
  //       : rootNode;

  //     if (candidateNode.output.length > 0) {
  //       const resultLength = candidateNode.output[0].length;
  //       const foundIndex = index - resultLength + 1;
  //       return {index: foundIndex, length: resultLength};
  //     }
  //   }

  //   return false;
  // },
  // // End _aho_corasick_search/3
  // // Deps: [:binary._parse_search_opts/1]

  // TODO: consider
  // // Start _boyer_moore_search/3
  // "_boyer_moore_search/3": (subject, pattern, options) => {
  //   const {start, length} = Erlang_Binary["_parse_search_opts/1"](options);
  //   const compiledPatternData = ERTS.binaryPatternRegistry.get(pattern);
  //   const badShift = compiledPatternData.badShift;

  //   Bitstring.maybeSetBytesFromText(subject);
  //   Bitstring.maybeSetBytesFromText(pattern);

  //   const patternMaxIndex = pattern.bytes.length - 1;
  //   let index = Math.max(start, 0);
  //   const maxIndex = Math.max(start + length, subject.bytes.length);

  //   while (index <= maxIndex) {
  //     let patternIndex = 0;
  //     while (
  //       pattern.bytes[patternIndex] === subject.bytes[patternIndex + index]
  //     ) {
  //       if (patternIndex === patternMaxIndex) {
  //         return {index, length: pattern.bytes.length};
  //       }
  //       patternIndex++;
  //     }

  //     const current = subject.bytes[index + patternMaxIndex];
  //     if (badShift[current]) {
  //       index += badShift[current];
  //     } else {
  //       index++;
  //     }
  //   }

  //   return false;
  // },
  // // End _boyer_moore_search/3
  // // Deps: [:binary._parse_search_opts/1]

  // TODO: consider
  // // Start _parse_search_opts/1
  // "_parse_search_opts/1": (opts) => {
  //   if (!Type.isList(opts)) {
  //     Interpreter.raiseFunctionClauseError(
  //       Interpreter.buildFunctionClauseErrorMsg("invalid options"),
  //     );
  //   }

  //   if (Type.isImproperList(opts)) {
  //     Interpreter.raiseFunctionClauseError(
  //       Interpreter.buildFunctionClauseErrorMsg("invalid options"),
  //     );
  //   }

  //   const scopeTuple = Erlang_Lists["keyfind/3"](
  //     Type.atom("scope"),
  //     Type.integer(1),
  //     opts,
  //   );

  //   if (scopeTuple && scopeTuple.data && scopeTuple.data.length == 2) {
  //     const innerData = scopeTuple.data[1];
  //     const start = innerData.data[0];
  //     const length = innerData.data[1];
  //     if (Type.isInteger(start) && Type.isInteger(length)) {
  //       return {start: Number(start.value), length: Number(length.value)};
  //     } else {
  //       Interpreter.raiseFunctionClauseError(
  //         Interpreter.buildFunctionClauseErrorMsg("invalid options"),
  //       );
  //     }
  //   } else {
  //     return {start: 0, length: -1};
  //   }
  // },
  // // End _parse_search_opts/1
  // // Deps: [:lists.keyfind/3]
};

export default Erlang_Binary;
