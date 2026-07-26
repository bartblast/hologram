"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang from "./erlang.mjs";
import ERTS from "../erts.mjs";
import Interpreter from "../interpreter.mjs";
import RegexEngine from "../regex/regex_engine.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Re = {
  // Start compile/1
  "compile/1": (pattern) => Erlang_Re["compile/2"](pattern, Type.list()),
  // End compile/1
  // Deps: [:re.compile/2]

  // Start compile/2
  "compile/2": (pattern, options) => {
    const CRLF_NEWLINE_TYPES = new Set(["any", "anycrlf", "crlf"]);

    // Compile option atoms passed to the engine under the same name.
    const ENGINE_OPTS = new Set([
      "bsr_anycrlf",
      "caseless",
      "dollar_endonly",
      "dotall",
      "dupnames",
      "extended",
      "multiline",
      "never_utf",
      "no_auto_capture",
      "ucp",
      "ungreedy",
    ]);

    const NEWLINE_TYPES = new Set([
      "any",
      "anycrlf",
      "cr",
      "crlf",
      "lf",
      "nul",
    ]);

    // Applies a compile option to the accumulator.
    // Returns false when the option is not a valid compile option.
    const applyOption = (option, acc) => {
      if (Type.isAtom(option)) {
        if (ENGINE_OPTS.has(option.value)) {
          acc.engineOpts[option.value] = true;
          return true;
        }

        switch (option.value) {
          case "anchored":
            acc.anchored = true;
            return true;

          case "bsr_unicode":
            acc.engineOpts.bsr_anycrlf = false;
            return true;

          case "firstline":
            acc.firstline = true;
            return true;

          case "no_start_optimize":
            return true;

          case "unicode":
            acc.unicodeOption = true;
            return true;

          default:
            return false;
        }
      }

      if (
        Type.isTuple(option) &&
        option.data.length === 2 &&
        Type.isAtom(option.data[0]) &&
        option.data[0].value === "newline" &&
        Type.isAtom(option.data[1]) &&
        NEWLINE_TYPES.has(option.data[1].value)
      ) {
        acc.engineOpts.newline = option.data[1].value;
        return true;
      }

      return false;
    };

    const buildErrorTuple = (message, position) =>
      Type.tuple([
        Type.atom("error"),
        Type.tuple([Type.charlist(message), Type.integer(position)]),
      ]);

    // Returns null when the options are not a proper list of valid
    // compile options.
    const parseOptions = () => {
      if (!Type.isProperList(options)) return null;

      const acc = {
        anchored: false,
        engineOpts: {},
        firstline: false,
        unicodeOption: false,
      };

      for (const option of options.data) {
        if (!applyOption(option, acc)) return null;
      }

      return acc;
    };

    const raiseCharDataError = () => {
      Interpreter.raiseArgumentError("argument error");
    };

    // Converts a char data list to a JS string, decoding contained binaries
    // from UTF-8. An improper char data list may only have a binary tail.
    const textFromCharData = (list) => {
      const isProper = Type.isProperList(list);
      const elementCount = isProper ? list.data.length : list.data.length - 1;
      let text = "";

      for (let index = 0; index < elementCount; index++) {
        const element = list.data[index];

        if (Type.isInteger(element)) {
          const codePoint = Number(element.value);

          if (
            codePoint < 0 ||
            codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff)
          ) {
            raiseCharDataError();
          }

          text += String.fromCodePoint(codePoint);
        } else if (Type.isBitstring(element)) {
          text += textFromCharDataBinary(element);
        } else if (Type.isList(element)) {
          text += textFromCharData(element);
        } else {
          raiseCharDataError();
        }
      }

      if (!isProper) {
        const tail = list.data[list.data.length - 1];

        if (!Type.isBitstring(tail)) raiseCharDataError();

        text += textFromCharDataBinary(tail);
      }

      return text;
    };

    const textFromCharDataBinary = (binary) => {
      if (!Type.isBinary(binary)) raiseCharDataError();

      Bitstring.maybeSetBytesFromText(binary);

      const decoded = RegexEngine.decodeUtf8(binary.bytes);

      if (decoded.error) raiseCharDataError();

      return decoded.text;
    };

    const parsedOptions = parseOptions();

    if (parsedOptions === null) {
      let patternIsIodata = true;

      try {
        Erlang["iolist_to_binary/1"](pattern);
      } catch {
        patternIsIodata = false;
      }

      const patternBullet = patternIsIodata
        ? ""
        : "  * 1st argument: not an iodata term\n";

      Interpreter.raiseArgumentError(
        `errors were found at the given arguments:\n\n${patternBullet}  * 2nd argument: invalid options\n`,
      );
    }

    const engineOpts = parsedOptions.engineOpts;
    let result;

    if (parsedOptions.unicodeOption) {
      engineOpts.unicode = true;

      let patternBytes = null;
      let patternText = null;

      if (Type.isBitstring(pattern)) {
        if (!Type.isBinary(pattern)) {
          Interpreter.raiseArgumentError(
            Interpreter.buildArgumentErrorMsg(1, "not an iodata term"),
          );
        }

        Bitstring.maybeSetBytesFromText(pattern);
        patternBytes = pattern.bytes;
      } else if (Type.isList(pattern)) {
        patternText = textFromCharData(pattern);
      } else {
        raiseCharDataError();
      }

      // The option clash beats UTF-8 validation of a binary pattern
      if (engineOpts.never_utf) {
        return buildErrorTuple("using UTF is disabled by the application", 0);
      }

      if (patternBytes !== null) {
        result = RegexEngine.compileBytes(patternBytes, engineOpts);
      } else {
        result = RegexEngine.compile(patternText, engineOpts);

        // Error positions are byte offsets in the pattern
        if (result.error) {
          result = {
            error: {
              message: result.error.message,
              position: RegexEngine.utf16IndexToByteOffset(
                patternText,
                result.error.position,
              ),
            },
          };
        }
      }
    } else {
      const binary = Erlang["iolist_to_binary/1"](pattern);

      Bitstring.maybeSetBytesFromText(binary);
      result = RegexEngine.compileBytes(binary.bytes, engineOpts);
    }

    if (result.error) {
      return buildErrorTuple(result.error.message, result.error.position);
    }

    const captureCount = result.groupMap.count;
    const useCrlf = CRLF_NEWLINE_TYPES.has(result.newlineType) ? 1 : 0;
    const ref = Erlang["make_ref/0"]();

    ERTS.regexPatternRegistry.put(ref, {
      anchored: parsedOptions.anchored,
      captureCount: captureCount,
      compiled: result,
      firstline: parsedOptions.firstline,
      unicode: result.opts.unicode === true,
    });

    return Type.tuple([
      Type.atom("ok"),
      Type.tuple([
        Type.atom("re_pattern"),
        Type.integer(captureCount),
        Type.integer(parsedOptions.unicodeOption ? 1 : 0),
        Type.integer(useCrlf),
        ref,
      ]),
    ]);
  },
  // End compile/2
  // Deps: [:erlang.iolist_to_binary/1, :erlang.make_ref/0]

  // Start import/1
  "import/1": (exportedPattern) => {
    const raiseNotExported = () => {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not an exported regular expression",
        ),
      );
    };

    const hasMagicPrefix = (binary, magic) => {
      if (!Type.isBinary(binary)) return false;

      Bitstring.maybeSetBytesFromText(binary);

      if (binary.bytes.length < magic.length) return false;

      return magic.every((byte, index) => binary.bytes[index] === byte);
    };

    if (
      !Type.isTuple(exportedPattern) ||
      exportedPattern.data.length !== 5 ||
      !Interpreter.isStrictlyEqual(
        exportedPattern.data[0],
        Type.atom("re_exported_pattern"),
      )
    ) {
      raiseNotExported();
    }

    const [_tag, header, source, options, code] = exportedPattern.data;

    // The header and code blobs carry PCRE2-native serialization the client
    // can't execute - the pattern is recompiled from source and options
    // instead, so blob validation is limited to the serialization magic
    // bytes ("re-PCRE2" and "S2RP") and the header size.
    if (
      !hasMagicPrefix(
        header,
        [..."re-PCRE2"].map((c) => c.charCodeAt(0)),
      ) ||
      header.bytes.length < 14 ||
      !hasMagicPrefix(
        code,
        [..."S2RP"].map((c) => c.charCodeAt(0)),
      )
    ) {
      raiseNotExported();
    }

    if (!Type.isProperList(options)) raiseNotExported();

    const compileOptions = Type.list(
      options.data.filter(
        (option) => !(Type.isAtom(option) && option.value === "export"),
      ),
    );

    let result;

    try {
      result = Erlang_Re["compile/2"](source, compileOptions);
    } catch {
      raiseNotExported();
    }

    // A compile error tuple can only come from a tampered source, since the
    // exported source has already compiled successfully
    if (!Interpreter.isStrictlyEqual(result.data[0], Type.atom("ok"))) {
      raiseNotExported();
    }

    return result.data[1];
  },
  // End import/1
  // Deps: [:re.compile/2]

  // Start inspect/2
  "inspect/2": (compiledPattern, item) => {
    const compareByUtf8Bytes = (name1, name2) => {
      const bytes1 = ERTS.utf8Encoder.encode(name1);
      const bytes2 = ERTS.utf8Encoder.encode(name2);
      const minLength = Math.min(bytes1.length, bytes2.length);

      for (let index = 0; index < minLength; index++) {
        if (bytes1[index] !== bytes2[index]) {
          return bytes1[index] - bytes2[index];
        }
      }

      return bytes1.length - bytes2.length;
    };

    const registryEntry =
      Type.isTuple(compiledPattern) &&
      compiledPattern.data.length === 5 &&
      Interpreter.isStrictlyEqual(
        compiledPattern.data[0],
        Type.atom("re_pattern"),
      )
        ? ERTS.regexPatternRegistry.get(compiledPattern.data[4])
        : null;

    if (registryEntry === null) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "not a compiled regular expression",
        ),
      );
    }

    if (!Interpreter.isStrictlyEqual(item, Type.atom("namelist"))) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid item"),
      );
    }

    // PCRE2 stores the name table sorted by the byte order of the names
    const names = [...registryEntry.compiled.groupMap.names.keys()].sort(
      compareByUtf8Bytes,
    );

    return Type.tuple([
      Type.atom("namelist"),
      Type.list(names.map((name) => Type.bitstring(name))),
    ]);
  },
  // End inspect/2
  // Deps: []

  // Start version/0
  "version/0": () => {
    // TODO: Replace hardcoded PCRE version with version captured from system at runtime
    return Type.bitstring("8.44 2020-02-12");
  },
  // End version/0
  // Deps: []
};

export default Erlang_Re;
