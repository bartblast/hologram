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
