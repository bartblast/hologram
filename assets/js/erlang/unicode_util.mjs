"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_UnicodeUtil = {
  // Start _cpl/2
  "_cpl/2": (list, restList) => {
    const isCP = Erlang_UnicodeUtil["_is_cp/1"];

    // [C] when is_integer(C)
    if (isCP(list)) {
      return Type.improperList([
        list,
        Erlang_UnicodeUtil["_cpl_1_cont/1"](restList),
      ]);
    }

    if (Type.isList(list) && list.data.length > 0) {
      // Inline optimized index-based logic to avoid O(n²) slicing behavior
      const result = [];
      let idx = 0;

      // Fast path: collect consecutive codepoints iteratively
      while (idx < list.data.length && isCP(list.data[idx])) {
        result.push(list.data[idx]);
        idx++;
      }

      // If we collected all remaining elements as codepoints
      if (idx >= list.data.length) {
        if (result.length === 0) {
          // When we've exhausted the nested list, check if restList starts with a binary
          if (restList.data.length > 0 && Type.isBinary(restList.data[0])) {
            return restList;
          }
          return Erlang_UnicodeUtil["cp/1"](restList);
        }
        // Merge collected codepoints with restList
        if (restList.data.length > 0 && Type.isBinary(restList.data[0])) {
          if (restList.data.length === 1) {
            return Type.improperList([...result, restList.data[0]]);
          }
          return Type.list([...result, ...restList.data]);
        }
        const restListResult = Erlang_UnicodeUtil["cp/1"](restList);
        if (Type.isList(restListResult) && restListResult.isProper) {
          return Type.list([...result, ...restListResult.data]);
        }
        return Type.improperList([...result, restListResult]);
      }

      // If we collected some codepoints but hit a non-codepoint element
      const firstElement = list.data[idx];

      if (idx === list.data.length - 1) {
        const contResult = Erlang_UnicodeUtil["_cpl_cont/2"](
          firstElement,
          restList,
        );
        if (result.length === 0) {
          return contResult;
        }
        if (Type.isList(contResult) && contResult.isProper) {
          return Type.list([...result, ...contResult.data]);
        }
        return Type.improperList([...result, contResult]);
      }

      const newRestList =
        restList.data.length === 0
          ? Type.list([Type.list(list.data.slice(idx + 1))])
          : Type.list([Type.list(list.data.slice(idx + 1)), ...restList.data]);
      const contResult = Erlang_UnicodeUtil["_cpl_cont/2"](
        firstElement,
        newRestList,
      );
      if (result.length === 0) {
        return contResult;
      }
      if (Type.isList(contResult) && contResult.isProper) {
        return Type.list([...result, ...contResult.data]);
      }
      return Type.improperList([...result, contResult]);
    }

    // []
    if (Type.isList(list) && list.data.length === 0) {
      // When we've exhausted the nested list, check if there's more to process
      // If restList starts with a binary, don't extract from it - just return restList
      // Otherwise, continue processing (e.g., for nested empty lists)
      if (restList.data.length > 0 && Type.isBinary(restList.data[0])) {
        // If next element in restList is binary, return it as-is (don't extract from it)
        return restList;
      }
      // Continue processing restList for non-binary elements or nested structures
      return Erlang_UnicodeUtil["cp/1"](restList);
    }

    // Binary handling: <<C/utf8, T/binary>>
    if (Type.isBinary(list)) {
      const text = Bitstring.toText(list);

      // Invalid UTF-8
      if (text === false) {
        const errorPayload = Erlang_UnicodeUtil["_merge_lcr/2"](list, restList);
        return Type.tuple([Type.atom("error"), errorPayload]);
      }

      if (text.length === 0) {
        return Erlang_UnicodeUtil["cp/1"](restList);
      }

      const codepoint = text.codePointAt(0);
      const charLength = codepoint > 0xffff ? 2 : 1;
      const restText = text.slice(charLength);
      const restBinary = Bitstring.fromText(restText);

      // If restList is improper with single element (the tail), create improper result
      if (!restList.isProper && restList.data.length === 1) {
        return Type.improperList([
          Type.integer(codepoint),
          restBinary,
          restList.data[0],
        ]);
      }

      return Type.list([Type.integer(codepoint), restBinary, ...restList.data]);
    }

    // Non-byte-aligned bitstring
    if (Type.isBitstring(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl/2", [
          list,
          restList,
        ]),
      );
    }

    // Should not reach here
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl/2", [
        list,
        restList,
      ]),
    );
  },
  // End _cpl/2
  // Deps: [:unicode_util._cpl_1_cont/1, :unicode_util._cpl_cont/2, :unicode_util._is_cp/1, :unicode_util._merge_lcr/2, :unicode_util.cp/1]

  // Start _cpl_1_cont/1
  "_cpl_1_cont/1": (restList) => {
    const isCP = Erlang_UnicodeUtil["_is_cp/1"];

    if (!Type.isList(restList)) {
      return restList;
    }

    if (restList.data.length === 0) {
      return restList;
    }

    const firstElement = restList.data[0];
    const tail = Type.list(restList.data.slice(1));

    // [C|T] when is_integer(C)
    if (isCP(firstElement)) {
      return Type.improperList([
        firstElement,
        Erlang_UnicodeUtil["_cpl_1_cont2/1"](tail),
      ]);
    }

    // [L|T]
    return Erlang_UnicodeUtil["_cpl_cont/2"](firstElement, tail);
  },
  // End _cpl_1_cont/1
  // Deps: [:unicode_util._cpl_1_cont2/1, :unicode_util._cpl_cont/2, :unicode_util._is_cp/1]

  // Start _cpl_1_cont2/1
  "_cpl_1_cont2/1": (restList) => {
    const isCP = Erlang_UnicodeUtil["_is_cp/1"];

    if (!Type.isList(restList)) {
      return restList;
    }

    if (restList.data.length === 0) {
      return restList;
    }

    const firstElement = restList.data[0];
    const tail = Type.list(restList.data.slice(1));

    // [C|T] when is_integer(C)
    if (isCP(firstElement)) {
      return Type.improperList([
        firstElement,
        Erlang_UnicodeUtil["_cpl_1_cont3/1"](tail),
      ]);
    }

    // [L]
    if (restList.data.length === 1) {
      return Erlang_UnicodeUtil["_cpl_1_cont2/1"](firstElement);
    }

    // [L|T]
    return Erlang_UnicodeUtil["_cpl_cont2/2"](firstElement, tail);
  },
  // End _cpl_1_cont2/1
  // Deps: [:unicode_util._cpl_1_cont3/1, :unicode_util._cpl_cont2/2, :unicode_util._is_cp/1]

  // Start _cpl_1_cont3/1
  "_cpl_1_cont3/1": (restList) => {
    const isCP = Erlang_UnicodeUtil["_is_cp/1"];

    if (!Type.isList(restList)) {
      return restList;
    }

    if (restList.data.length === 0) {
      return restList;
    }

    const firstElement = restList.data[0];

    // [C|_]=T when is_integer(C)
    if (isCP(firstElement)) {
      return restList;
    }

    // [L]
    if (restList.data.length === 1) {
      return Erlang_UnicodeUtil["_cpl_1_cont3/1"](firstElement);
    }

    // [L|T]
    const tail = Type.list(restList.data.slice(1));
    return Erlang_UnicodeUtil["_cpl_cont3/2"](firstElement, tail);
  },
  // End _cpl_1_cont3/1
  // Deps: [:unicode_util._cpl_cont3/2, :unicode_util._is_cp/1]

  // Start _cpl_cont/2
  "_cpl_cont/2": (list, restList) => {
    if (Type.isList(list) && list.data.length > 0) {
      // Inline optimized index-based logic to avoid O(n²) slicing behavior
      const isCP = Erlang_UnicodeUtil["_is_cp/1"];
      const result = [];
      let idx = 0;

      // Fast path: collect consecutive codepoints iteratively
      while (idx < list.data.length && isCP(list.data[idx])) {
        result.push(list.data[idx]);
        idx++;
      }

      // If we collected all remaining elements as codepoints
      if (idx >= list.data.length) {
        if (result.length === 0) {
          if (restList.data.length > 0 && Type.isBinary(restList.data[0])) {
            return restList;
          }
          return Erlang_UnicodeUtil["cp/1"](restList);
        }
        if (restList.data.length > 0 && Type.isBinary(restList.data[0])) {
          if (restList.data.length === 1) {
            return Type.improperList([...result, restList.data[0]]);
          }
          return Type.list([...result, ...restList.data]);
        }
        const restListResult = Erlang_UnicodeUtil["cp/1"](restList);
        if (Type.isList(restListResult) && restListResult.isProper) {
          return Type.list([...result, ...restListResult.data]);
        }
        return Type.improperList([...result, restListResult]);
      }

      const firstElement = list.data[idx];

      if (idx === list.data.length - 1) {
        const cplResult = Erlang_UnicodeUtil["_cpl/2"](firstElement, restList);
        if (result.length === 0) {
          return cplResult;
        }
        if (Type.isList(cplResult) && cplResult.isProper) {
          return Type.list([...result, ...cplResult.data]);
        }
        return Type.improperList([...result, cplResult]);
      }

      const newRestList =
        restList.data.length === 0
          ? Type.list([Type.list(list.data.slice(idx + 1))])
          : Type.list([Type.list(list.data.slice(idx + 1)), ...restList.data]);
      const cplResult = Erlang_UnicodeUtil["_cpl/2"](firstElement, newRestList);
      if (result.length === 0) {
        return cplResult;
      }
      if (Type.isList(cplResult) && cplResult.isProper) {
        return Type.list([...result, ...cplResult.data]);
      }
      return Type.improperList([...result, cplResult]);
    }

    // []
    if (Type.isList(list) && list.data.length === 0) {
      return Erlang_UnicodeUtil["cp/1"](restList);
    }

    // Binary handling: <<C/utf8, T/binary>>
    if (Type.isBinary(list)) {
      const text = Bitstring.toText(list);

      // Invalid UTF-8: return error tuple
      if (text === false) {
        const errorPayload = Erlang_UnicodeUtil["_merge_lcr/2"](list, restList);
        return Type.tuple([Type.atom("error"), errorPayload]);
      }

      if (text.length === 0) {
        return Erlang_UnicodeUtil["cp/1"](restList);
      }

      const codepoint = text.codePointAt(0);
      // Calculate character length in UTF-16 code units (surrogate pairs are 2 units)
      const charLength = codepoint > 0xffff ? 2 : 1;
      const restText = text.slice(charLength);
      const restBinary = Bitstring.fromText(restText);

      // If restList is improper (has a non-list tail), propagate improper structure
      if (!restList.isProper && restList.data.length === 1) {
        // Append extracted codepoint and remaining binary, then the original tail
        return Type.improperList([
          Type.integer(codepoint),
          restBinary,
          restList.data[0],
        ]);
      }

      // Proper list: prepend extracted codepoint and remaining binary to restList elements
      return Type.list([Type.integer(codepoint), restBinary, ...restList.data]);
    }

    // Non-byte-aligned bitstring
    if (Type.isBitstring(list)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl_cont/2", [
          list,
          restList,
        ]),
      );
    }

    // Should not reach here
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cpl_cont/2", [
        list,
        restList,
      ]),
    );
  },
  // End _cpl_cont/2
  // Deps: [:unicode_util._cpl/2, :unicode_util._is_cp/1, :unicode_util._merge_lcr/2, :unicode_util.cp/1]

  // Start _cpl_cont2/2
  "_cpl_cont2/2": (list, restList) => {
    if (Type.isList(list) && list.data.length > 0) {
      // Inline optimized index-based logic to avoid O(n²) slicing behavior
      const isCP = Erlang_UnicodeUtil["_is_cp/1"];
      const result = [];
      let idx = 0;

      // Fast path: collect consecutive codepoints iteratively
      while (idx < list.data.length && isCP(list.data[idx])) {
        result.push(list.data[idx]);
        idx++;
      }

      if (idx >= list.data.length) {
        if (result.length === 0) {
          return restList;
        }
        // For improper list continuation, chain codepoints
        let current = restList;
        for (let i = result.length - 1; i >= 0; i--) {
          current = Type.improperList([result[i], current]);
        }
        return current;
      }

      const firstElement = list.data[idx];

      if (idx === list.data.length - 1) {
        const cont2Result = Erlang_UnicodeUtil["_cpl_1_cont2/1"](
          Type.list([firstElement, ...restList.data]),
        );
        if (result.length === 0) {
          return cont2Result;
        }
        let current = cont2Result;
        for (let i = result.length - 1; i >= 0; i--) {
          current = Type.improperList([result[i], current]);
        }
        return current;
      }

      const newRestList =
        restList.data.length === 0
          ? Type.list([Type.list(list.data.slice(idx + 1))])
          : Type.list([Type.list(list.data.slice(idx + 1)), ...restList.data]);
      const cont2Result = Erlang_UnicodeUtil["_cpl_cont2/2"](
        firstElement,
        newRestList,
      );
      if (result.length === 0) {
        return cont2Result;
      }
      let current = cont2Result;
      for (let i = result.length - 1; i >= 0; i--) {
        current = Type.improperList([result[i], current]);
      }
      return current;
    }

    return restList;
  },
  // End _cpl_cont2/2
  // Deps: [:unicode_util._cpl_1_cont2/1, :unicode_util._is_cp/1]

  // Start _cpl_cont3/2
  "_cpl_cont3/2": (list, restList) => {
    if (Type.isList(list) && list.data.length > 0) {
      // Inline optimized index-based logic to avoid O(n²) slicing behavior
      const isCP = Erlang_UnicodeUtil["_is_cp/1"];
      const result = [];
      let idx = 0;

      // Fast path: collect consecutive codepoints iteratively
      while (idx < list.data.length && isCP(list.data[idx])) {
        result.push(list.data[idx]);
        idx++;
      }

      if (idx >= list.data.length) {
        if (result.length === 0) {
          return restList;
        }
        // For improper list continuation, chain codepoints
        let current = restList;
        for (let i = result.length - 1; i >= 0; i--) {
          current = Type.improperList([result[i], current]);
        }
        return current;
      }

      const firstElement = list.data[idx];

      if (idx === list.data.length - 1) {
        const cont3Result = Erlang_UnicodeUtil["_cpl_1_cont3/1"](
          Type.list([firstElement, ...restList.data]),
        );
        if (result.length === 0) {
          return cont3Result;
        }
        let current = cont3Result;
        for (let i = result.length - 1; i >= 0; i--) {
          current = Type.improperList([result[i], current]);
        }
        return current;
      }

      const newRestList =
        restList.data.length === 0
          ? Type.list([Type.list(list.data.slice(idx + 1))])
          : Type.list([Type.list(list.data.slice(idx + 1)), ...restList.data]);
      const cont3Result = Erlang_UnicodeUtil["_cpl_cont3/2"](
        firstElement,
        newRestList,
      );
      if (result.length === 0) {
        return cont3Result;
      }
      let current = cont3Result;
      for (let i = result.length - 1; i >= 0; i--) {
        current = Type.improperList([result[i], current]);
      }
      return current;
    }

    return restList;
  },
  // End _cpl_cont3/2
  // Deps: [:unicode_util._cpl_1_cont3/1, :unicode_util._is_cp/1]

  // Start _is_cp/1
  "_is_cp/1": (value) => {
    if (!Type.isInteger(value)) {
      return false;
    }
    const codepoint = Number(value.value);
    return codepoint >= 0 && codepoint <= 0x10ffff;
  },
  // End _is_cp/1
  // Deps: []

  // Start _merge_lcr/2
  "_merge_lcr/2": (binary, restList) => {
    // Combine an invalid binary with a rest list for error reporting
    // If rest list is empty or not a list, return just the binary
    if (!Type.isList(restList) || restList.data.length === 0) {
      return binary;
    }

    // Prepend binary to rest list elements
    return Type.list([binary, ...restList.data]);
  },
  // End _merge_lcr/2
  // Deps: []

  // Start cp/1
  "cp/1": (string) => {
    const isCP = Erlang_UnicodeUtil["_is_cp/1"];

    // [C|_] when is_integer(C)
    if (Type.isList(string) && string.data.length > 0 && isCP(string.data[0])) {
      return string;
    }

    // [List]
    if (Type.isList(string) && string.data.length === 1) {
      return Erlang_UnicodeUtil["cp/1"](string.data[0]);
    }

    // [List|R] - proper list with multiple elements
    if (Type.isList(string) && string.isProper && string.data.length > 1) {
      const restList = Type.list(string.data.slice(1));
      return Erlang_UnicodeUtil["_cpl/2"](string.data[0], restList);
    }

    // [List|Tail] - improper list (tail is not a list)
    if (Type.isList(string) && !string.isProper && string.data.length === 2) {
      const head = string.data[0];
      const tail = string.data[1];

      // If head is empty list, continue with tail
      if (Type.isList(head) && head.data.length === 0) {
        return Erlang_UnicodeUtil["cp/1"](tail);
      }

      // If head is empty binary, continue with tail
      if (Type.isBinary(head) && Bitstring.isEmpty(head)) {
        return Erlang_UnicodeUtil["cp/1"](tail);
      }

      // If tail is empty list, treat as proper list [head]
      if (Type.isList(tail) && tail.data.length === 0) {
        return Erlang_UnicodeUtil["cp/1"](head);
      }

      // For other cases, process head element and combine result with tail
      // Case: head is a binary - extract first codepoint from it
      if (Type.isBinary(head)) {
        const text = Bitstring.toText(head);
        if (text === false) {
          return Type.tuple([Type.atom("error"), head]);
        }
        if (text.length === 0) {
          return Erlang_UnicodeUtil["cp/1"](tail);
        }
        const codepoint = text.codePointAt(0);
        const charLength = codepoint > 0xffff ? 2 : 1;
        const restText = text.slice(charLength);
        const restBinary = Bitstring.fromText(restText);

        // Create improper list: [codepoint | [restBinary | tail]]
        return Type.improperList([Type.integer(codepoint), restBinary, tail]);
      }

      // Case: head is a list - recursively process it, then append tail
      if (Type.isList(head)) {
        const headResult = Erlang_UnicodeUtil["cp/1"](head);
        // If head processing yielded empty list, continue with tail
        if (Type.isList(headResult) && headResult.data.length === 0) {
          return Erlang_UnicodeUtil["cp/1"](tail);
        }
        // If head processing yielded a list (proper or improper), append tail
        if (Type.isList(headResult)) {
          return Type.improperList([...headResult.data, tail]);
        }
      }

      // Fallback - shouldn't reach here
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [string]),
      );
    }

    // []
    if (Type.isList(string) && string.data.length === 0) {
      return Type.list();
    }

    // <<C/utf8, R/binary>>
    if (Type.isBinary(string)) {
      const text = Bitstring.toText(string);

      // Invalid UTF-8
      if (text === false) {
        return Type.tuple([Type.atom("error"), string]);
      }

      if (text.length === 0) {
        return Type.list();
      }

      const codepoint = text.codePointAt(0);
      // Calculate character length in UTF-16 code units (surrogate pairs are 2 units)
      const charLength = codepoint > 0xffff ? 2 : 1;
      const restText = text.slice(charLength);
      const restBinary = Bitstring.fromText(restText);

      // Return improper list: [codepoint | restBinary] - codepoint followed by remaining binary
      return Type.improperList([Type.integer(codepoint), restBinary]);
    }

    // <<>>
    if (Type.isBitstring(string) && Bitstring.isEmpty(string)) {
      return Type.list();
    }

    // All other cases: invalid input type (including non-byte-aligned bitstrings)
    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":unicode_util.cp/1", [string]),
    );
  },
  // End cp/1
  // Deps: [:unicode_util._cpl/2, :unicode_util._is_cp/1]
};

export default Erlang_UnicodeUtil;
