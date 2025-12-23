"use strict";

import Bitstring from "../bitstring.mjs";
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
      return Erlang_Binary._boyer_moore_pattern_matcher(pattern);
    } else if (
      Type.isList(pattern) &&
      pattern.data.length > 0 &&
      pattern.data.every((i) => Type.isBinary(i))
    ) {
      return pattern.length == 1
        ? Erlang_Binary._boyer_moore_pattern_matcher(pattern.data[0])
        : Erlang_Binary._aho_corasick_pattern_matcher(pattern);
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

  // Boyer-Moore matcher implementation for single patterns
  // Start _boyer_moore_pattern_matcher/1
  _boyer_moore_pattern_matcher: (pattern) => {
    Bitstring.maybeSetBytesFromText(pattern);

    if (pattern.bytes.length == 0) {
      Interpreter.raiseArgumentError("is not a valid pattern");
    }

    const length = pattern.bytes.length - 1;

    // Seed the badShift object with an initial value of -1 for each byte
    const badShift = {};
    for (let i = 0; i < 256; i++) {
      badShift[i] = -1;
    }

    // Overwrite with the actual value for each byte in the pattern
    pattern.bytes.forEach((byte, index) => {
      badShift[byte] = length - index;
    });

    const ref = Erlang["make_ref/0"]();
    ERTS.binaryPatternRegistry.put(ref, pattern);

    return Type.tuple([Type.atom("bm"), ref]);
  },
  // End _boyer_moore_pattern_matcher/1
  // Deps: []

  // Aho-Corasick matcher implementation for multiple patterns
  // Start _aho_corasick_pattern_matcher/1
  _aho_corasick_pattern_matcher: (patterns) => {
    const root = {
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

    const ref = Erlang["make_ref/0"]();
    ERTS.binaryPatternRegistry.put(ref, patterns);

    return Type.tuple([Type.atom("ac"), ref]);
  },
  // End _aho_corasick_pattern_matcher/1
  // Deps: []
};

export default Erlang_Binary;
