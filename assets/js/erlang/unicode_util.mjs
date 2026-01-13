"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_UnicodeUtil = {
  // Start cp/1
  "cp/1": (arg) => {
    // Constants
    const MAX_UNICODE_CODEPOINT = 0x10ffff;
    const SURROGATE_MIN = 0xd800; // 55296
    const SURROGATE_MAX = 0xdfff; // 57343
    const BMP_MAX = 0xffff;

    // Helper functions
    const errorTuple = (binary) => Type.tuple([Type.atom("error"), binary]);

    const isSurrogatePair = (codepoint) =>
      codepoint >= SURROGATE_MIN && codepoint <= SURROGATE_MAX;

    const extractCodepointFromText = (text) => {
      const firstCodePoint = text.codePointAt(0);
      const charLength = firstCodePoint > BMP_MAX ? 2 : 1;
      const restOfString = text.slice(charLength);

      if (isSurrogatePair(firstCodePoint)) {
        return {error: true};
      }

      return {firstCodePoint, restOfString};
    };

    const validateByteAligned = (bitstring, context) => {
      if (bitstring.leftoverBitCount !== 0) {
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            context,
          ]),
        );
      }
    };

    const isErrorResult = (result) =>
      result && typeof result === "object" && "isError" in result;

    const isCodepointResult = (result) =>
      result && typeof result === "object" && "codepoint" in result;

    const isNestedResult = (result) =>
      result && typeof result === "object" && "isNestedResult" in result;

    // Handle binary input
    if (Type.isBinary(arg)) {
      const text = Bitstring.toText(arg);

      // Check for invalid UTF-8 - return error tuple
      if (text === false) {
        return errorTuple(arg);
      }

      // Empty binary returns empty list
      if (text.length === 0) {
        return Type.list();
      }

      // Extract first codepoint
      const extraction = extractCodepointFromText(text);
      if (extraction.error) {
        return errorTuple(arg);
      }

      // Return [codepoint | rest_binary]
      return Type.improperList([
        Type.integer(extraction.firstCodePoint),
        Type.bitstring(extraction.restOfString),
      ]);
    }

    // Handle list input
    if (Type.isList(arg)) {
      // Empty list returns empty list
      if (arg.data.length === 0) {
        return Type.list();
      }

      const processListElement = (element) => {
        // Handle integer element
        if (Type.isInteger(element)) {
          const codepoint = Number(element.value);

          // Validate codepoint range
          if (codepoint < 0 || codepoint > MAX_UNICODE_CODEPOINT) {
            Interpreter.raiseFunctionClauseError(
              Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
                element,
              ]),
            );
          }

          return element;
        }

        // Handle bitstring element
        if (Type.isBitstring(element)) {
          validateByteAligned(element, element);

          const text = Bitstring.toText(element);

          // Check for invalid UTF-8 - return error tuple
          if (text === false) {
            return {isError: true, binary: element};
          }

          // Empty binary, continue processing
          if (text.length === 0) {
            return null; // Signal to skip this element
          }

          // Extract first codepoint from binary
          const extraction = extractCodepointFromText(text);
          if (extraction.error) {
            return {isError: true, binary: element};
          }

          // Return codepoint and rest (always include rest, even if empty)
          return {
            codepoint: Type.integer(extraction.firstCodePoint),
            rest: Type.bitstring(extraction.restOfString),
          };
        }

        // Handle nested list element
        if (Type.isList(element)) {
          // Recursively process nested list
          const result = Erlang_UnicodeUtil["cp/1"](element);

          // If nested list is empty, return null to skip
          if (result.data.length === 0) {
            return null;
          }

          // If result is improper list, mark it so the tail can be handled specially
          return {
            isNestedResult: true,
            elements: result.data,
            isImproper: Type.isImproperList(result),
          };
        }

        // Invalid element type
        Interpreter.raiseFunctionClauseError(
          Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [
            element,
          ]),
        );
      };

      // Process first element
      const firstElement = arg.data[0];
      const processedFirst = processListElement(firstElement);

      // If error tuple, return it
      if (isErrorResult(processedFirst)) {
        return errorTuple(processedFirst.binary);
      }

      // If first element is null (empty), try next elements
      if (processedFirst === null) {
        const restList = Type.list(arg.data.slice(1));
        return Erlang_UnicodeUtil["cp/1"](restList);
      }

      // Handle codepoint result from binary
      if (isCodepointResult(processedFirst)) {
        if (arg.data.length === 1) {
          return Type.improperList([
            processedFirst.codepoint,
            processedFirst.rest,
          ]);
        }

        return Type.list([
          processedFirst.codepoint,
          processedFirst.rest,
          ...arg.data.slice(1),
        ]);
      }

      // Handle nested list result
      if (isNestedResult(processedFirst)) {
        const result = [];

        if (processedFirst.isImproper) {
          const elements = processedFirst.elements;
          const tail = elements[elements.length - 1];

          result.push(...elements.slice(0, -1));

          // Only add tail if it's not an empty binary
          if (!Type.isBitstring(tail) || tail.text.length > 0) {
            result.push(tail);
          }
        } else {
          result.push(...processedFirst.elements);
        }

        result.push(...arg.data.slice(1));
        return Type.list(result);
      }

      // Handle regular integer
      return Type.list([processedFirst, ...arg.data.slice(1)]);
    }

    // Handle non-byte-aligned bitstring
    if (Type.isBitstring(arg)) {
      validateByteAligned(arg, arg);
    }

    // Invalid input type
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [arg]),
    );
  },
  // End cp/1
  // Deps: []
};

export default Erlang_UnicodeUtil;
