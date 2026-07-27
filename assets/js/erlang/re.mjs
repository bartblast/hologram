"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang from "./erlang.mjs";
import ERTS from "../erts.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
import Interpreter from "../interpreter.mjs";
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
        if (ERTS.regex.parseCompileOption(option, acc) === "invalid") {
          return null;
        }
      }

      return acc;
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
      } else {
        patternText = ERTS.regex.charDataToText(pattern);
      }

      // The option clash beats UTF-8 validation of a binary pattern
      if (engineOpts.never_utf) {
        return buildErrorTuple("using UTF is disabled by the application", 0);
      }

      if (patternBytes !== null) {
        result = ERTS.regex.compileBytes(patternBytes, engineOpts);
      } else {
        result = ERTS.regex.compile(patternText, engineOpts);

        // Error positions are byte offsets in the pattern
        if (result.error) {
          result = {
            error: {
              message: result.error.message,
              position: ERTS.regex.utf16IndexToByteOffset(
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
      result = ERTS.regex.compileBytes(binary.bytes, engineOpts);
    }

    if (result.error) {
      return buildErrorTuple(result.error.message, result.error.position);
    }

    const captureCount = result.groupMap.count;
    const useCrlf = ERTS.regex.usesCrlf(result.newlineType) ? 1 : 0;
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
      ERTS.regex.compareByUtf8Bytes,
    );

    return Type.tuple([
      Type.atom("namelist"),
      Type.list(names.map((name) => Type.bitstring(name))),
    ]);
  },
  // End inspect/2
  // Deps: []

  // Start run/2
  "run/2": (subject, pattern) =>
    Erlang_Re["run/3"](subject, pattern, Type.list()),
  // End run/2
  // Deps: [:re.run/3]

  // Start run/3
  "run/3": (subject, pattern, options) => {
    const CAPTURE_KIND_ATOMS = new Set([
      "all",
      "all_but_first",
      "all_names",
      "first",
      "none",
    ]);

    const CAPTURE_TYPE_ATOMS = new Set(["binary", "index", "list"]);

    // Limit tuple option tags mapped to engine run option names.
    const LIMIT_TUPLE_KEYS = {
      match_limit: "matchLimit",
      match_limit_recursion: "matchLimitRecursion",
    };

    // Group indices, offsets and match limits are limited to the positive
    // range of a 32-bit integer
    const MAX_INT32 = 2_147_483_647n;

    // Scan flag option atoms mapped to engine run option names.
    const RUN_FLAG_KEYS = {
      notbol: "notbol",
      noteol: "noteol",
      notempty: "notempty",
      notempty_atstart: "notemptyAtStart",
    };

    // Run-only option atoms not yet supported.
    // TODO: implement the report_errors run option.
    const RUN_ONLY_ATOMS = new Set(["report_errors"]);

    const raiseArgumentError = () => {
      Interpreter.raiseArgumentError("argument error");
    };

    const raiseNotImplemented = (option) => {
      throw new HologramInterpreterError(
        `the ${Interpreter.inspect(option)} option is not yet implemented in Hologram`,
      );
    };

    // --- Options ---

    const acc = {
      anchored: false,
      engineOpts: {},
      firstline: false,
      unicodeOption: false,
    };

    const runFlags = {
      notbol: false,
      noteol: false,
      notempty: false,
      notemptyAtStart: false,
    };

    let captureOption = null;
    let compileOnlyOptionUsed = false;
    let isGlobal = false;
    let notImplementedOption = null;

    const limitOptions = {
      matchLimit: undefined,
      matchLimitRecursion: undefined,
    };

    let dualOptionUsed = false;
    let offsetOption = null;
    let optionsValid = Type.isProperList(options);

    const isBoundedInteger = (term) =>
      Type.isInteger(term) && term.value >= 0n && term.value <= MAX_INT32;

    if (optionsValid) {
      for (const option of options.data) {
        if (Type.isAtom(option) && option.value === "global") {
          isGlobal = true;
          continue;
        }

        if (Type.isAtom(option) && Object.hasOwn(RUN_FLAG_KEYS, option.value)) {
          runFlags[RUN_FLAG_KEYS[option.value]] = true;
          continue;
        }

        const isCapture =
          Type.isTuple(option) &&
          (option.data.length === 2 || option.data.length === 3) &&
          Interpreter.isStrictlyEqual(option.data[0], Type.atom("capture"));

        // The last capture option wins
        if (isCapture) {
          captureOption = option;
          continue;
        }

        const isOffset =
          Type.isTuple(option) &&
          option.data.length === 2 &&
          Interpreter.isStrictlyEqual(option.data[0], Type.atom("offset"));

        if (isOffset) {
          if (!isBoundedInteger(option.data[1])) {
            optionsValid = false;
            break;
          }

          // The last offset option wins
          offsetOption = Number(option.data[1].value);
          continue;
        }

        const isLimit =
          Type.isTuple(option) &&
          option.data.length === 2 &&
          Type.isAtom(option.data[0]) &&
          Object.hasOwn(LIMIT_TUPLE_KEYS, option.data[0].value);

        if (isLimit) {
          if (!isBoundedInteger(option.data[1])) {
            optionsValid = false;
            break;
          }

          // The last limit option of each kind wins
          limitOptions[LIMIT_TUPLE_KEYS[option.data[0].value]] = Number(
            option.data[1].value,
          );

          continue;
        }

        const isRunOnly =
          Type.isAtom(option) && RUN_ONLY_ATOMS.has(option.value);

        if (isRunOnly) {
          notImplementedOption ??= option;
          continue;
        }

        switch (ERTS.regex.parseCompileOption(option, acc)) {
          case "compile":
            compileOnlyOptionUsed = true;
            break;

          case "dual":
            dualOptionUsed = true;
            break;

          case "invalid":
            optionsValid = false;
            break;
        }

        if (!optionsValid) break;
      }
    }

    // --- Pattern (validation phase) ---

    const registryEntry =
      Type.isTuple(pattern) &&
      pattern.data.length === 5 &&
      Interpreter.isStrictlyEqual(pattern.data[0], Type.atom("re_pattern"))
        ? ERTS.regexPatternRegistry.get(pattern.data[4])
        : null;

    let entry = null;
    let patternBullet = null;
    let patternRaisesArgumentError = false;

    if (registryEntry !== null) {
      entry = {
        anchored: registryEntry.anchored,
        compiled: registryEntry.compiled,
        firstline: registryEntry.firstline,
        unicode: registryEntry.unicode,
      };
    } else if (acc.unicodeOption) {
      // In unicode mode only the pattern term shape is validated here.
      // The pattern resolves later, as char data conversion failures raise
      // plain ArgumentError instead of contributing a bullet.
      if (!Type.isBinary(pattern) && !Type.isList(pattern)) {
        patternBullet =
          "neither an iodata term nor a compiled regular expression";
      }
    } else {
      // In byte mode the pattern resolves during validation
      let patternBinary = null;

      try {
        patternBinary = Erlang["iolist_to_binary/1"](pattern);
      } catch {
        patternBullet =
          "neither an iodata term nor a compiled regular expression";
      }

      if (patternBinary !== null) {
        Bitstring.maybeSetBytesFromText(patternBinary);

        const result = ERTS.regex.compileBytes(
          patternBinary.bytes,
          acc.engineOpts,
        );

        if (result.error) {
          if (
            result.error.message === "using UTF is disabled by the application"
          ) {
            patternRaisesArgumentError = true;
          } else {
            patternBullet = `could not parse regular expression\n${result.error.message} on character ${result.error.position}`;
          }
        } else {
          entry = {
            anchored: acc.anchored,
            compiled: result,
            firstline: acc.firstline,
            unicode: result.opts.unicode === true,
          };
        }
      }
    }

    // --- Subject (validation phase) ---

    // The subject is validated as iodata unless it is consumed as char data,
    // which happens with the unicode option or a unicode compiled pattern
    const byteModeSubject =
      !acc.unicodeOption && !(registryEntry !== null && registryEntry.unicode);

    let subjectBinary = null;
    let subjectBullet = null;

    if (byteModeSubject) {
      try {
        subjectBinary = Erlang["iolist_to_binary/1"](subject);
      } catch {
        subjectBullet = "not an iodata term";
      }
    }

    // --- Combined validation errors ---

    if (subjectBullet !== null || patternBullet !== null || !optionsValid) {
      const bullets = [
        subjectBullet === null ? "" : `  * 1st argument: ${subjectBullet}\n`,
        patternBullet === null ? "" : `  * 2nd argument: ${patternBullet}\n`,
        optionsValid ? "" : "  * 3rd argument: invalid options\n",
      ].join("");

      Interpreter.raiseArgumentError(
        `errors were found at the given arguments:\n\n${bullets}`,
      );
    }

    if (patternRaisesArgumentError) raiseArgumentError();

    // Compile options, including the dual newline and bsr options, don't
    // apply to an already compiled pattern
    if (
      registryEntry !== null &&
      (compileOnlyOptionUsed || dualOptionUsed || acc.unicodeOption)
    ) {
      raiseArgumentError();
    }

    // --- Pattern (unicode resolution phase) ---

    let subjectText = null;

    if (entry === null) {
      acc.engineOpts.unicode = true;

      // The subject char data converts before the pattern compiles
      subjectText = ERTS.regex.charDataToText(subject);

      const patternText = ERTS.regex.charDataToText(pattern);

      // The option clash raises instead of returning a compile error tuple
      if (acc.engineOpts.never_utf) raiseArgumentError();

      const result = ERTS.regex.compile(patternText, acc.engineOpts);

      if (result.error) {
        // Error positions are byte offsets in the pattern
        const position = ERTS.regex.utf16IndexToByteOffset(
          patternText,
          result.error.position,
        );

        Interpreter.raiseArgumentError(
          Interpreter.buildArgumentErrorMsg(
            2,
            `could not parse regular expression\n${result.error.message} on character ${position}`,
          ),
        );
      }

      entry = {
        anchored: acc.anchored,
        compiled: result,
        firstline: acc.firstline,
        unicode: true,
      };
    }

    // --- Capture spec (validation phase) ---

    // The spec content is validated before matching, so an invalid spec
    // raises even when the subject wouldn't match
    let captureKind = "all";
    let captureTargets = null;
    let captureType = "index";

    if (captureOption !== null) {
      if (captureOption.data.length === 3) {
        const typeTerm = captureOption.data[2];

        if (!Type.isAtom(typeTerm) || !CAPTURE_TYPE_ATOMS.has(typeTerm.value)) {
          raiseArgumentError();
        }

        captureType = typeTerm.value;
      }

      const valueSpec = captureOption.data[1];

      if (Type.isAtom(valueSpec) && CAPTURE_KIND_ATOMS.has(valueSpec.value)) {
        captureKind = valueSpec.value;
      } else if (Type.isProperList(valueSpec)) {
        captureKind = "explicit";

        captureTargets = valueSpec.data.map((element) => {
          if (Type.isInteger(element)) {
            if (element.value < 0n || element.value > MAX_INT32) {
              raiseArgumentError();
            }

            return {number: Number(element.value)};
          }

          if (Type.isAtom(element)) return {name: element.value};

          if (Type.isBitstring(element)) {
            if (!Type.isBinary(element)) raiseArgumentError();

            Bitstring.maybeSetBytesFromText(element);

            // An invalid UTF-8 name can't match any group name, which makes
            // it an unset capture rather than an error
            const decoded = ERTS.regex.decodeUtf8(element.bytes);

            return {name: decoded.error ? null : decoded.text};
          }

          if (Type.isList(element)) {
            return {name: ERTS.regex.charDataToText(element)};
          }

          raiseArgumentError();
        });
      } else {
        raiseArgumentError();
      }
    }

    // --- Options not yet supported ---

    if (notImplementedOption !== null) {
      raiseNotImplemented(notImplementedOption);
    }

    // --- Subject resolution ---

    if (subjectText === null) {
      if (entry.unicode) {
        subjectText = ERTS.regex.charDataToText(subject);
      } else {
        Bitstring.maybeSetBytesFromText(subjectBinary);
        subjectText = ERTS.regex.textFromLatin1Bytes(subjectBinary.bytes);
      }
    }

    // --- Start position ---

    // The offset is a byte offset into the subject
    let offsetBeyondSubject = false;
    let startPosition = 0;

    if (offsetOption !== null) {
      if (entry.unicode) {
        startPosition = ERTS.regex.byteOffsetToUtf16Index(
          subjectText,
          offsetOption,
        );

        if (
          ERTS.regex.utf16IndexToByteOffset(subjectText, startPosition) !==
          offsetOption
        ) {
          const subjectByteLength = ERTS.regex.utf16IndexToByteOffset(
            subjectText,
            subjectText.length,
          );

          // An offset inside a character raises even in a global run
          if (offsetOption > subjectByteLength) {
            offsetBeyondSubject = true;
          } else {
            raiseArgumentError();
          }
        }
      } else {
        // In byte mode JS string indices are byte offsets already
        offsetBeyondSubject = offsetOption > subjectText.length;
        startPosition = offsetOption;
      }

      // A global run treats an offset beyond the subject as no match found
      if (offsetBeyondSubject) {
        if (isGlobal) return Type.atom("nomatch");

        raiseArgumentError();
      }
    }

    // --- Match ---

    const engineRunOpts = {
      anchored: entry.anchored || acc.anchored,
      firstline: entry.firstline,
      matchLimit: limitOptions.matchLimit,
      matchLimitRecursion: limitOptions.matchLimitRecursion,
      notbol: runFlags.notbol,
      noteol: runFlags.noteol,
      notempty: runFlags.notempty,
      notemptyAtStart: runFlags.notemptyAtStart,
      startPosition: startPosition,
    };

    let matchResults;

    if (isGlobal) {
      matchResults = ERTS.regex.matchGlobal(
        entry.compiled,
        subjectText,
        engineRunOpts,
      );
    } else {
      const matchResult = ERTS.regex.match(
        entry.compiled,
        subjectText,
        engineRunOpts,
      );

      matchResults = matchResult === null ? [] : [matchResult];
    }

    if (matchResults.length === 0) return Type.atom("nomatch");

    // --- Captures ---

    const groupMap = entry.compiled.groupMap;

    // The none spec, an empty capture list and all_names without named
    // groups yield a bare :match
    if (
      captureKind === "none" ||
      (captureKind === "explicit" && captureTargets.length === 0) ||
      (captureKind === "all_names" && groupMap.names.size === 0)
    ) {
      return Type.atom("match");
    }

    // PCRE2 stores the name table sorted by the byte order of the names
    const sortedNames =
      captureKind === "all_names"
        ? [...groupMap.names.keys()].sort(ERTS.regex.compareByUtf8Bytes)
        : null;

    // In byte mode JS string indices are byte offsets already
    const toByteOffset = entry.unicode
      ? (index) => ERTS.regex.utf16IndexToByteOffset(subjectText, index)
      : (index) => index;

    const buildValue = (capture) => {
      switch (captureType) {
        case "binary": {
          if (capture === null) return Type.bitstring("");

          const slice = subjectText.slice(capture.start, capture.end);

          return entry.unicode
            ? Type.bitstring(slice)
            : Bitstring.fromBytes([...slice].map((char) => char.charCodeAt(0)));
        }

        case "index": {
          if (capture === null) {
            return Type.tuple([Type.integer(-1), Type.integer(0)]);
          }

          const start = toByteOffset(capture.start);
          const length = toByteOffset(capture.end) - start;

          return Type.tuple([Type.integer(start), Type.integer(length)]);
        }

        case "list": {
          if (capture === null) return Type.list();

          const slice = subjectText.slice(capture.start, capture.end);

          return Type.list(
            [...slice].map((char) => Type.integer(char.codePointAt(0))),
          );
        }
      }
    };

    // Returns the boxed capture list of a single match result
    const shapeMatch = (matchResult) => {
      // Returns {start, end} in JS string indices, or null when the group
      // is unset or doesn't exist
      const captureForNumber = (number) => {
        if (number === 0) {
          return {start: matchResult.start, end: matchResult.end};
        }

        if (number > groupMap.count) return null;

        return matchResult.captures[number];
      };

      // With dupnames a name maps to multiple group numbers, of which the
      // first set one wins
      const captureForName = (name) => {
        const numbers = groupMap.names.get(name);

        if (numbers === undefined) return null;

        for (const number of numbers) {
          const capture = captureForNumber(number);
          if (capture !== null) return capture;
        }

        return null;
      };

      const captureForTarget = (target) =>
        "number" in target
          ? captureForNumber(target.number)
          : captureForName(target.name);

      let captures;

      switch (captureKind) {
        case "all":
        case "all_but_first":
          captures = [];

          for (
            let number = captureKind === "all" ? 0 : 1;
            number <= groupMap.count;
            number++
          ) {
            captures.push(captureForNumber(number));
          }

          // Trailing unset groups are not reported
          while (
            captures.length > 0 &&
            captures[captures.length - 1] === null
          ) {
            captures.pop();
          }
          break;

        case "all_names":
          captures = sortedNames.map(captureForName);
          break;

        case "explicit":
          captures = captureTargets.map(captureForTarget);
          break;

        case "first":
          captures = [captureForNumber(0)];
          break;
      }

      return Type.list(captures.map(buildValue));
    };

    const captured = isGlobal
      ? Type.list(matchResults.map(shapeMatch))
      : shapeMatch(matchResults[0]);

    return Type.tuple([Type.atom("match"), captured]);
  },
  // End run/3
  // Deps: [:erlang.iolist_to_binary/1]

  // Start version/0
  "version/0": () => {
    // TODO: Replace hardcoded PCRE version with version captured from system at runtime
    return Type.bitstring("8.44 2020-02-12");
  },
  // End version/0
  // Deps: []
};

export default Erlang_Re;
