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

  // Boyer-Moore matcher implementation for single patterns
  // Start _boyer_moore_pattern_matcher/1
  "_boyer_moore_pattern_matcher/1": (pattern) => {
    Bitstring.maybeSetBytesFromText(pattern);

    if (pattern.bytes.length == 0) {
      Interpreter.raiseArgumentError("is not a valid pattern");
    }

    let badShift;
    if (!ERTS.binaryPatternRegistry.get(pattern)) {
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

      const compiledPatternData = {type: "bm", badShift};
      ERTS.binaryPatternRegistry.put(pattern, compiledPatternData);
    }

    const ref = Erlang["make_ref/0"]();
    return Type.tuple([Type.atom("bm"), ref]);
  },
  // End _boyer_moore_pattern_matcher/1
  // Deps: [:erlang.make_ref/0]

  // Start _boyer_moore_search/3
  "_boyer_moore_search/3": (subject, pattern, options) => {
    const {start, length} = Erlang_Binary["_parse_search_opts/1"](options);
    const compiledPatternData = ERTS.binaryPatternRegistry.get(pattern);
    const badShift = compiledPatternData.badShift;

    Bitstring.maybeSetTextFromBytes(subject);
    Bitstring.maybeSetTextFromBytes(pattern);

    const patternMaxIndex = pattern.text.length - 1;
    let index = Math.max(start, 0);
    const maxIndex = Math.max(length, subject.text.length);

    while (index <= maxIndex) {
      let patternIndex = 0;
      while (
        pattern.text[patternIndex] === subject.text[patternIndex + index]
      ) {
        if (patternIndex === patternMaxIndex) {
          return {index, length: pattern.text.length};
        }
        patternIndex++;
      }

      const current = subject[index + patternMaxIndex];
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
  "_aho_corasick_pattern_matcher/1": (patterns) => {
    if (!ERTS.binaryPatternRegistry.get(patterns)) {
      const rootNode = {
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

      const compiledPatternData = {type: "ac", rootNode};
      ERTS.binaryPatternRegistry.put(patterns, compiledPatternData);
    }

    const ref = Erlang["make_ref/0"]();
    return Type.tuple([Type.atom("ac"), ref]);
  },
  // End _aho_corasick_pattern_matcher/1
  // Deps: [:erlang.make_ref/0]

  // Start _aho_corasick_search/3
  "_aho_corasick_search/3": (subject, patterns, options) => {
    const {start, length} = Erlang_Binary["_parse_search_opts/1"](options);
    const compiledPatternData = ERTS.binaryPatternRegistry.get(patterns);

    Bitstring.maybeSetBytesFromText(subject);
    const startIndex = Math.max(start, 0);
    const maxIndex = Math.max(length, subject.text.length);

    const rootNode = compiledPatternData.rootNode;
    let currentNode = rootNode;

    for (let index = startIndex; index < maxIndex; index++) {
      const char = subject.bytes[index];

      // console.log("index:", index);
      // console.log("char:", char);
      // console.log(
      //   "currentNode.children.get(char):",
      //   currentNode.children.get(char),
      // );

      while (currentNode !== null && !currentNode.children.get(char)) {
        currentNode = currentNode.failure;
      }

      currentNode = currentNode
        ? currentNode.children[char] || this.root
        : this.root;

      // console.log("output:", currentNode.output);

      const resultLength = currentNode.output.length;
      const foundIndex = index - resultLength + 1;
      return Type.tuple([Type.integer(foundIndex), Type.integer(resultLength)]);
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

    if (scopeTuple && scopeTuple.data && scopeTuple.data.length == 2) {
      const innerData = scopeTuple.data[1];
      const start = innerData.data[0];
      const length = innerData.data[1];
      if (Type.isInteger(start) && Type.isInteger(length)) {
        return {start: Number(start.value), length: Number(length.value)};
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
