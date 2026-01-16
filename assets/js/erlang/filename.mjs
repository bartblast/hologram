"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";
import Erlang from "./erlang.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Filename = {
  // Start _do_flatten/2
  "_do_flatten/2": (filename, tail) => {
    if (Type.isList(filename)) {
      const flattenElement = (acc, elem) => {
        if (Type.isList(elem)) {
          return Erlang_Filename["_do_flatten/2"](elem, acc);
        }

        if (Type.isAtom(elem)) {
          const atomAsCharlist = Erlang["atom_to_list/1"](elem);
          const combined = [...atomAsCharlist.data, ...acc.data];
          return Type.list(combined);
        }

        const combined = [elem, ...acc.data];
        return Type.list(combined);
      };

      return filename.data.reduceRight(flattenElement, tail);
    }

    if (Type.isAtom(filename)) {
      const atomAsCharlist = Erlang["atom_to_list/1"](filename);
      const combined = [...atomAsCharlist.data, ...tail.data];
      return Type.list(combined);
    }

    if (Type.isBinary(filename)) {
      const combined = [filename, ...tail.data];
      return Type.list(combined);
    }

    Interpreter.raiseFunctionClauseError(
      Interpreter.buildFunctionClauseErrorMsg(":filename.do_flatten/2", [
        filename,
        tail,
      ]),
    );
  },
  // End _do_flatten/2
  // Deps: [:erlang.atom_to_list/1]

  // Start _dirname_raw/1
  "_dirname_raw/1": (filenameBinary) => {
    // Helpers

    const computeResultBytes = (
      lastSlashIndex,
      trimmedBytes,
      DIR_SEPARATOR_BYTE,
    ) => {
      if (lastSlashIndex === -1) return [46]; // No separator found - return '.'

      // lastSlashIndex is the distance from end (reversed index);
      // if equal to length-1, the separator is at position 0 (array start), meaning root
      if (lastSlashIndex === trimmedBytes.length - 1) {
        return [DIR_SEPARATOR_BYTE]; // Only separator at start - return '/'
      }

      // Return bytes before the last separator (convert reversed index back to normal index)
      // Formula: normal_index = array_length - 1 - reversed_index
      return trimmedBytes.slice(0, trimmedBytes.length - 1 - lastSlashIndex);
    };

    // Search from end of array; returns reversed index (distance from end)
    // Example: [47, 47, 65] with separator 47 returns 1 (A is 1 position from end)
    const findLastNonSeparatorIndex = (bytes, DIR_SEPARATOR_BYTE) => {
      const reversed = [...bytes].reverse();
      const index = reversed.findIndex((byte) => byte !== DIR_SEPARATOR_BYTE);

      return index === -1 ? -1 : index;
    };

    // Search from end of array; returns reversed index (distance from end)
    // Example: [65, 47, 66] with separator 47 returns 1 (separator is 1 position from end)
    const findLastSeparatorIndex = (bytes, DIR_SEPARATOR_BYTE) => {
      const reversed = [...bytes].reverse();
      const index = reversed.findIndex((byte) => byte === DIR_SEPARATOR_BYTE);

      return index === -1 ? -1 : index;
    };

    // Main logic

    const DIR_SEPARATOR_BYTE = 47; // '/'
    const bytes = filenameBinary.bytes;

    // Trim trailing separators
    const reversedIndex = findLastNonSeparatorIndex(bytes, DIR_SEPARATOR_BYTE);

    // All separators - return single separator
    if (reversedIndex === -1) {
      const result = Bitstring.fromBytes([DIR_SEPARATOR_BYTE]);
      Bitstring.maybeSetTextFromBytes(result);
      return result;
    }

    const trimmedBytes = bytes.slice(0, bytes.length - reversedIndex);

    // Find last separator in trimmed bytes
    const lastSlashIndex = findLastSeparatorIndex(
      trimmedBytes,
      DIR_SEPARATOR_BYTE,
    );

    const resultBytes = computeResultBytes(
      lastSlashIndex,
      trimmedBytes,
      DIR_SEPARATOR_BYTE,
    );

    const result = Bitstring.fromBytes(resultBytes);
    Bitstring.maybeSetTextFromBytes(result);

    return result;
  },
  // End _dirname_raw/1

  // Start basename/1
  "basename/1": (filename) => {
    const DIR_SEPARATOR_BYTE = 47;

    // flatten/1 handles argument type checking and raises
    // FunctionClauseError if needed.
    const flattened = Erlang_Filename["flatten/1"](filename);

    // TODO: Once implemented, replace extractBasenameBytes with :binary.split/3
    // on <<"/">> with [global] option, filter out <<>>.
    const extractBasenameBytes = (bytes) => {
      const lastNonSeparatorIndex = [...bytes]
        .reverse()
        .findIndex((byte) => byte !== DIR_SEPARATOR_BYTE);

      if (lastNonSeparatorIndex === -1) {
        return null;
      }

      const end = bytes.length - lastNonSeparatorIndex;
      const bytesUpToEnd = bytes.slice(0, end);

      const lastSeparatorIndex = [...bytesUpToEnd]
        .reverse()
        .findIndex((byte) => byte === DIR_SEPARATOR_BYTE);

      const start =
        lastSeparatorIndex === -1
          ? 0
          : bytesUpToEnd.length - lastSeparatorIndex;

      return bytes.slice(start, end);
    };

    const getBinaryAndValidateUtf8 = (flattened, isBinary) => {
      const binary = isBinary
        ? flattened
        : Erlang["iolist_to_binary/1"](flattened);

      Bitstring.maybeSetBytesFromText(binary);
      const bytes = binary.bytes;
      const component = extractBasenameBytes(bytes);

      if (component === null) {
        return {component: null, basenameBinary: null, isValidUtf8: true};
      }

      const basenameBinary = Bitstring.fromBytes(component);
      Bitstring.maybeSetTextFromBytes(basenameBinary);

      return {
        component,
        basenameBinary,
        isValidUtf8: basenameBinary.text !== false,
      };
    };

    const handleBinaryFilename = (flattened) => {
      if (Bitstring.isEmpty(flattened)) {
        return Type.bitstring("");
      }

      const {component, basenameBinary, isValidUtf8} = getBinaryAndValidateUtf8(
        flattened,
        true,
      );

      if (component === null) {
        return Type.bitstring("");
      }

      if (!isValidUtf8) {
        // For invalid UTF-8, return bitstring with text: null to preserve raw bytes
        return Bitstring.fromBytes(component);
      }

      return Type.bitstring(basenameBinary.text);
    };

    const handleListFilename = (flattened) => {
      const {component, basenameBinary, isValidUtf8} = getBinaryAndValidateUtf8(
        flattened,
        false,
      );

      if (component === null) {
        return Type.list([]);
      }

      if (!isValidUtf8) {
        // For invalid UTF-8, return raw bytes as integers
        return Type.list([...component].map((byte) => Type.integer(byte)));
      }

      return Bitstring.toCodepoints(basenameBinary);
    };

    const result = Type.isBinary(flattened)
      ? handleBinaryFilename(flattened)
      : handleListFilename(flattened);

    return result;
  },
  // End basename/1
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1]

  // Start basename/2
  "basename/2": (filename, ext) => {
    // flatten/1 handles argument type checking and raises FunctionClauseError if needed.
    const flattenedFilename = Erlang_Filename["flatten/1"](filename);
    const flattenedExt = Erlang_Filename["flatten/1"](ext);

    // Get the basename using basename/1
    const bname = Erlang_Filename["basename/1"](flattenedFilename);
    const bnameIsBinary = Type.isBinary(bname);

    // Convert both to binary for comparison (to simplify logic)
    let bnameAsBinary = bname;
    if (!bnameIsBinary) {
      bnameAsBinary = Erlang["iolist_to_binary/1"](bname);
    }

    let extAsBinary = flattenedExt;
    if (!Type.isBinary(extAsBinary)) {
      extAsBinary = Erlang["iolist_to_binary/1"](extAsBinary);
    }

    // Make shallow copies to avoid modifying original values
    // Note: maybeSetBytesFromText() only populates fields if missing - it doesn't mutate byte arrays
    const bnameForComparison = {...bnameAsBinary};
    const extForComparison = {...extAsBinary};

    // Ensure we have bytes for comparison
    Bitstring.maybeSetBytesFromText(bnameForComparison);
    Bitstring.maybeSetBytesFromText(extForComparison);

    const bnameBytes = bnameForComparison.bytes;
    const extBytes = extForComparison.bytes;

    // If extension is longer than basename, return basename as-is
    if (extBytes.length > bnameBytes.length) return bname;

    // Check if basename ends with extension
    let extMatches = true;
    for (let i = 0; i < extBytes.length; i++) {
      if (bnameBytes[bnameBytes.length - extBytes.length + i] !== extBytes[i]) {
        extMatches = false;
        break;
      }
    }

    if (!extMatches) return bname;

    // Extension matches - remove it and return the result
    // Important: Erlang's basename/2 returns binary when extension is binary, regardless of filename type
    const partLength = bnameBytes.length - extBytes.length;

    // TODO: Once :erlang.binary_part/3 can be used with slices, replace this with:
    // const resultBinary = Erlang["binary_part/3"](bnameAsBinary, Type.integer(0), Type.integer(partLength))
    const resultBytes = bnameBytes.slice(0, partLength);

    const extIsBinary = Type.isBinary(flattenedExt);
    const resultBinary = Bitstring.fromBytes(resultBytes);
    Bitstring.maybeSetTextFromBytes(resultBinary);

    if (resultBinary.text === false) {
      // Invalid UTF-8, preserve raw bytes
      return extIsBinary
        ? resultBinary
        : Type.list([...resultBytes].map((byte) => Type.integer(byte)));
    }

    // Valid UTF-8
    // Return as binary if extension is binary OR original basename was binary
    // Return as charlist only if both filename and extension are lists
    return extIsBinary || bnameIsBinary
      ? Type.bitstring(resultBinary.text)
      : Bitstring.toCodepoints(resultBinary);
  },
  // End basename/2
  // Deps: [:erlang.iolist_to_binary/1, :filename.basename/1, :filename.flatten/1]

  // Start dirname/1
  "dirname/1": (filename) => {
    // Helpers

    const computeDirname = (text) => {
      // For paths without trailing slashes: dirname is everything before last slash
      const lastSlashIndex = text.lastIndexOf("/");

      if (lastSlashIndex === -1) return "."; // Single component - dirname is current directory

      if (lastSlashIndex === 0) return "/"; // Root-relative path - dirname is root

      // Multi-component path - return everything before last slash
      return text.substring(0, lastSlashIndex);
    };

    // Handle trailing slashes: the trimmed directory path IS the parent directory
    // (trailing slash indicates the argument itself is a directory, not a filename)
    const computeDirnameWithTrailingSlashes = (trimmedText) => {
      if (trimmedText.length === 0) return "/"; // Original was all slashes

      return trimmedText;
    };

    // Extract trimmed text and detect trailing slashes in single pass
    const extractTrimmedTextAndTrailingSlashes = (text) => {
      // Regex ^(.*?)\/*$ captures everything before trailing slashes
      // Comparing trimmed length to original length tells us if trailing slashes existed
      const match = text.match(/^(.*?)\/*$/);
      const trimmedText = match[1];
      // If trimmed text is shorter, there were trailing slashes that were stripped
      const hasTrailingSlashes = trimmedText.length < text.length;

      return {trimmedText, hasTrailingSlashes};
    };

    // Handle invalid UTF-8 result
    const handleInvalidUtf8Result = (rawResult, isBinaryInput) => {
      if (rawResult.text !== false) {
        // Result turned out to be valid UTF-8 (e.g., ".")
        const resultBinary = Type.bitstring(rawResult.text);

        return isBinaryInput
          ? resultBinary
          : Bitstring.toCodepoints(resultBinary);
      }

      if (isBinaryInput) return rawResult;

      // Return raw bytes as list of integers
      Bitstring.maybeSetBytesFromText(rawResult);
      const result = Type.list(
        [...rawResult.bytes].map((byte) => Type.integer(byte)),
      );

      return result;
    };

    // Main logic

    // flatten/1 handles argument type checking and raises
    // FunctionClauseError if needed.
    const flattened = Erlang_Filename["flatten/1"](filename);
    const isBinaryInput = Type.isBinary(flattened);

    const binary = isBinaryInput
      ? flattened
      : Erlang["iolist_to_binary/1"](flattened);

    Bitstring.maybeSetBytesFromText(binary);
    Bitstring.maybeSetTextFromBytes(binary);

    // Handle invalid UTF-8
    if (binary.text === false) {
      const rawResult = Erlang_Filename["_dirname_raw/1"](binary);

      return handleInvalidUtf8Result(rawResult, isBinaryInput);
    }

    // Handle valid UTF-8 - extract trimmed text and detect trailing slashes in one pass
    const {trimmedText, hasTrailingSlashes} =
      extractTrimmedTextAndTrailingSlashes(binary.text);

    const resultText = hasTrailingSlashes
      ? computeDirnameWithTrailingSlashes(trimmedText)
      : computeDirname(trimmedText);

    const resultBinary = Type.bitstring(resultText);

    // Return result in the same format as input
    return isBinaryInput ? resultBinary : Bitstring.toCodepoints(resultBinary);
  },
  // End dirname/1
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1, :filename._dirname_raw/1]

  // Start extension/1
  "extension/1": (filename) => {
    // Helper functions

    const asBinary = (component) => {
      if (Type.isBinary(component)) {
        Bitstring.maybeSetBytesFromText(component);
        return component;
      }

      const binary = Erlang["iolist_to_binary/1"](component);
      Bitstring.maybeSetBytesFromText(binary);
      return binary;
    };

    const findBasenameWindow = (bytes) => {
      const lastNonSlashIndex = bytes.findLastIndex((byte) => byte !== 47);
      if (lastNonSlashIndex === -1) {
        return null;
      }

      const lastSlashBeforeBasename = bytes
        .subarray(0, lastNonSlashIndex + 1)
        .findLastIndex((byte) => byte === 47);

      const start =
        lastSlashBeforeBasename === -1 ? 0 : lastSlashBeforeBasename + 1;
      const end = lastNonSlashIndex + 1; // exclusive

      return {start, end};
    };

    const findExtensionBytes = (bytes, start, end) => {
      const basenameSlice = bytes.subarray(start, end);
      const lastDotInBasename = basenameSlice.findLastIndex(
        (byte) => byte === 46,
      );

      // No dot, or dot at basename start (e.g., ".bashrc")
      if (lastDotInBasename <= 0) {
        return null;
      }

      return bytes.slice(start + lastDotInBasename, end);
    };

    const renderEmpty = () =>
      outputIsBinary ? Type.bitstring("") : Type.list([]);

    const renderInvalid = (extensionBinary) =>
      outputIsBinary
        ? extensionBinary
        : Type.list(
            [...extensionBinary.bytes].map((byte) => Type.integer(byte)),
          );

    // Main logic

    // flatten/1 handles argument type checking and raises FunctionClauseError if needed.
    const flattened = Erlang_Filename["flatten/1"](filename);
    const outputIsBinary = Type.isBinary(flattened);

    // Work on bytes directly
    const filenameBinary = asBinary(flattened);
    const bytes = filenameBinary.bytes;

    // Empty input yields empty extension
    if (bytes.length === 0) {
      return renderEmpty();
    }

    // Locate basename window (after last slash, trimmed of trailing slashes)
    const basenameWindow = findBasenameWindow(bytes);
    if (!basenameWindow) {
      return renderEmpty();
    }

    const {start: basenameStart, end: basenameEnd} = basenameWindow;

    // Extract extension bytes from basename
    const extensionBytes = findExtensionBytes(
      bytes,
      basenameStart,
      basenameEnd,
    );
    if (extensionBytes === null) {
      return renderEmpty();
    }

    const extensionBinary = Bitstring.fromBytes(extensionBytes);
    Bitstring.maybeSetTextFromBytes(extensionBinary);

    // Preserve invalid UTF-8 as raw bytes
    if (extensionBinary.text === false) {
      return renderInvalid(extensionBinary);
    }

    if (outputIsBinary) {
      return Type.bitstring(extensionBinary.text);
    }

    return Bitstring.toCodepoints(extensionBinary);
  },
  // End extension/1
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1]

  // Start flatten/1
  "flatten/1": (filename) => {
    if (Type.isBinary(filename)) {
      return filename;
    }

    return Erlang_Filename["_do_flatten/2"](filename, Type.list());
  },
  // End flatten/1
  // Deps: [:filename._do_flatten/2]

  // Start join/1
  "join/1": (components) => {
    if (!Type.isList(components) || components.data.length === 0) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/1", [
          components,
        ]),
      );
    }

    // Single component: normalize via join/2 with empty second arg to handle
    // trailing slashes and ensure consistent path format (e.g., "foo/" becomes "foo")
    if (components.data.length === 1) {
      return Erlang_Filename["join/2"](components.data[0], Type.bitstring(""));
    }

    // Join multiple components using fold/reduce via join/2
    const joinedResult = components.data
      .slice(1)
      .reduce(
        (acc, component) => Erlang_Filename["join/2"](acc, component),
        components.data[0],
      );

    return joinedResult;
  },
  // End join/1
  // Deps: [:filename.join/2]

  // Start join/2
  "join/2": (name1, name2) => {
    const DIR_SEPARATOR_BYTE = 47;

    // Validate and type-check inputs first before calling flatten
    const isValidInput = (value) =>
      Type.isBinary(value) || Type.isList(value) || Type.isAtom(value);

    if (!isValidInput(name1) || !isValidInput(name2)) {
      Interpreter.raiseFunctionClauseError(
        Interpreter.buildFunctionClauseErrorMsg(":filename.join/2", [
          name1,
          name2,
        ]),
      );
    }

    // Helper functions

    // Converts byte array to Bitstring and validates UTF-8 encoding
    const convertBytesToBinary = (bytes) => {
      const resultBinary = Bitstring.fromBytes(bytes);
      Bitstring.maybeSetTextFromBytes(resultBinary);
      return resultBinary;
    };

    // Converts flattened input to binary (iolist → binary if needed)
    const getBinaryFromFlattened = (flattened, wasOriginallyBinary) => {
      return wasOriginallyBinary
        ? flattened
        : Erlang["iolist_to_binary/1"](flattened);
    };

    // Joins two byte arrays with a separator between them
    const joinPathBytes = (trimmed1, bytes2) => {
      if (trimmed1.length === 0 && bytes2.length === 0) {
        return [];
      }
      if (trimmed1.length === 0) {
        return [DIR_SEPARATOR_BYTE, ...bytes2];
      }
      return [...trimmed1, DIR_SEPARATOR_BYTE, ...bytes2];
    };

    const reconstructPath = (partsData, isAbsolute) => {
      const {parts, currentPart} = partsData;
      const allParts = currentPart.length > 0 ? [...parts, currentPart] : parts;

      // Filter out single-dot components (current directory references),
      // but preserve the first dot in relative paths (e.g., "./foo")
      const DOT_BYTE = 46; // ASCII code for "."
      const isSingleDot = (part) => part.length === 1 && part[0] === DOT_BYTE;

      const filteredParts = allParts.filter((part, index) => {
        // Keep the first part even if it's a single dot (for relative paths)
        if (index === 0) return true;

        // Filter out non-first single-dot components
        return !isSingleDot(part);
      });

      if (filteredParts.length === 0) {
        return isAbsolute ? [DIR_SEPARATOR_BYTE] : [];
      }

      // Build result using reduce with internal mutation for O(n) complexity
      return filteredParts.reduce(
        (acc, part, index) => {
          if (index > 0) {
            acc.push(DIR_SEPARATOR_BYTE);
          }
          acc.push(...part);
          return acc;
        },
        isAbsolute ? [DIR_SEPARATOR_BYTE] : [],
      );
    };

    const resultToOutput = (normalizedBytes, returnAsCodepoints) => {
      const resultBinary = convertBytesToBinary(normalizedBytes);

      // Handle invalid UTF-8: preserve raw bytes
      if (resultBinary.text === false) {
        return returnAsCodepoints
          ? Type.list([...normalizedBytes].map((byte) => Type.integer(byte)))
          : resultBinary;
      }

      // Valid UTF-8: return as bitstring or charlist
      const result = Type.bitstring(resultBinary.text);
      return returnAsCodepoints ? Bitstring.toCodepoints(result) : result;
    };

    const splitPathBytes = (bytes) => {
      // Use reduce with internal accumulator mutation for O(n) complexity
      const result = bytes.reduce(
        (acc, byte, index) => {
          if (byte !== DIR_SEPARATOR_BYTE) {
            acc.currentPart.push(byte);
            return acc;
          }

          // Handle separator: push current part if non-empty.
          // Leading separators (index === 0) are skipped here since they indicate
          // an absolute path, which is tracked separately via isResultAbsolute.
          if (index > 0 && acc.currentPart.length > 0) {
            acc.parts.push(acc.currentPart);
            acc.currentPart = [];
          }

          return acc;
        },
        {parts: [], currentPart: []},
      );

      return result;
    };

    const trimTrailingSeparators = (bytes) => {
      if (bytes.length === 0) return [];

      // Count trailing separators by finding last non-separator from the end
      const reversedIndex = [...bytes]
        .reverse()
        .findIndex((byte) => byte !== DIR_SEPARATOR_BYTE);

      if (reversedIndex === -1) return [];

      return bytes.slice(0, bytes.length - reversedIndex);
    };

    // Main logic

    const flattened1 = Erlang_Filename["flatten/1"](name1);
    const flattened2 = Erlang_Filename["flatten/1"](name2);

    // Determine return type: charlist (codepoints) only if BOTH inputs are list/atom,
    // otherwise return bitstring (matches Erlang behavior)
    const returnAsCodepoints =
      (Type.isList(name1) || Type.isAtom(name1)) &&
      (Type.isList(name2) || Type.isAtom(name2));

    const binary1 = getBinaryFromFlattened(flattened1, Type.isBinary(name1));
    const binary2 = getBinaryFromFlattened(flattened2, Type.isBinary(name2));

    // Ensure bitstrings have byte representations for manipulation
    Bitstring.maybeSetBytesFromText(binary1);
    Bitstring.maybeSetBytesFromText(binary2);

    const bytes1 = binary1.bytes;
    const bytes2 = binary2.bytes;

    // Check if name2 is absolute (starts with /)
    const isName2Absolute =
      bytes2.length > 0 && bytes2[0] === DIR_SEPARATOR_BYTE;

    // Determine result bytes based on path type:
    // - Absolute name2: use name2 only (e.g., "/usr" + "/local" = "/local")
    // - Empty name2: return name1 unchanged (e.g., "/" + "" = "/")
    // - Relative name2: join paths with separator after trimming trailing slashes
    const resultBytes = (() => {
      if (isName2Absolute) return bytes2;
      if (bytes2.length === 0) return bytes1;
      return joinPathBytes(trimTrailingSeparators(bytes1), bytes2);
    })();

    // Normalize path: split by separators, filter out "." components, reconstruct
    // This handles cases like "./foo/bar/./baz" becomes "./foo/bar/baz"
    const isResultAbsolute =
      resultBytes.length > 0 && resultBytes[0] === DIR_SEPARATOR_BYTE;
    const partsData = splitPathBytes(resultBytes);
    const normalizedBytes = reconstructPath(partsData, isResultAbsolute);

    // Convert back to appropriate output format
    return resultToOutput(normalizedBytes, returnAsCodepoints);
  },
  // End join/2
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1]

  // Start split/1
  "split/1": (filename) => {
    const DIR_SEPARATOR_BYTE = 47;

    // flatten/1 handles argument type checking and raises FunctionClauseError if needed.
    const flattened = Erlang_Filename["flatten/1"](filename);
    const flattenedIsBinary = Type.isBinary(flattened);

    // Early return for empty input
    if (
      flattenedIsBinary
        ? Bitstring.isEmpty(flattened)
        : flattened.data.length === 0
    ) {
      return Type.list();
    }

    // TODO: Once implemented, use :binary.split/3 on <<"/">> with [global] option
    // and filter out empty components.
    const splitPathBytes = (bytes) => {
      const {parts, currentPart} = [...bytes].reduce(
        (acc, byte, index) => {
          if (byte === DIR_SEPARATOR_BYTE) {
            // Handle leading slash - add "/" component
            if (index === 0) {
              acc.parts.push([DIR_SEPARATOR_BYTE]);
              return acc;
            }
            // Add non-empty accumulated part
            if (acc.currentPart.length > 0) {
              acc.parts.push(acc.currentPart);
              acc.currentPart = [];
            }
            return acc;
          }

          // Accumulate non-separator byte
          acc.currentPart.push(byte);
          return acc;
        },
        {parts: [], currentPart: []},
      );

      // Add final part if non-empty (trailing slashes are ignored)
      if (currentPart.length > 0) {
        parts.push(currentPart);
      }

      return parts;
    };

    // Convert to binary and split into byte arrays
    const binary = flattenedIsBinary
      ? flattened
      : Erlang["iolist_to_binary/1"](flattened);

    Bitstring.maybeSetBytesFromText(binary);
    const parts = splitPathBytes(binary.bytes);

    // Map byte arrays to appropriate output format
    const resultParts = parts.map((partBytes) => {
      const partBinary = Bitstring.fromBytes(partBytes);
      Bitstring.maybeSetTextFromBytes(partBinary);

      // Handle invalid UTF-8
      if (partBinary.text === false) {
        return flattenedIsBinary
          ? partBinary // Preserve raw bytes in bitstring
          : Type.list([...partBytes].map((byte) => Type.integer(byte)));
      }

      // Valid UTF-8
      return flattenedIsBinary
        ? Type.bitstring(partBinary.text)
        : Bitstring.toCodepoints(partBinary);
    });

    return Type.list(resultParts);
  },
  // End split/1
  // Deps: [:erlang.iolist_to_binary/1, :filename.flatten/1]
};

export default Erlang_Filename;
