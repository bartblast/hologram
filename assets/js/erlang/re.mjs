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
  "compile/1": (pattern) => {
    try {
      return Erlang_Re["compile/2"](pattern, Type.list());
    } catch (error) {
      if (error.struct) {
        // Re-raise with this function's own identity - the BEAM reports the
        // called function's frame, not the delegate's.
        Interpreter.raiseBifError(
          "badarg",
          "re",
          "compile",
          [pattern],
          "erl_stdlib_errors",
        );
      }

      throw error;
    }
  },
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
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "compile",
        [pattern, options],
        "erl_stdlib_errors",
        "badopt",
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
          Interpreter.raiseBifError(
            "badarg",
            "re",
            "compile",
            [pattern, options],
            "erl_stdlib_errors",
          );
        }

        Bitstring.maybeSetBytesFromText(pattern);
        patternBytes = pattern.bytes;
      } else {
        patternText = ERTS.regex.charDataToText(pattern);

        // The server raise carries no error_info here - the frame comes
        // from OTP's ucompile wrapper, not from a BIF.
        if (patternText === null) {
          Interpreter.raiseBifError(
            "badarg",
            "re",
            "compile",
            [pattern, options],
            null,
          );
        }
      }

      // The option clash beats UTF-8 validation of a binary pattern
      if (engineOpts.never_utf) {
        return buildErrorTuple("using UTF is disabled by the application", 0);
      }

      if (patternBytes !== null) {
        result = ERTS.regex.compileBytes(patternBytes, engineOpts);
      } else {
        result = ERTS.regex.compileText(patternText, engineOpts);
      }
    } else {
      let binary;

      try {
        binary = Erlang["iolist_to_binary/1"](pattern);
      } catch (error) {
        if (error.struct) {
          // Re-raise with this function's own identity - the BEAM reports
          // the BIF's frame, not the conversion's.
          Interpreter.raiseBifError(
            "badarg",
            "re",
            "compile",
            [pattern, options],
            "erl_stdlib_errors",
          );
        }

        throw error;
      }

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
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "import",
        [exportedPattern],
        "erl_stdlib_errors",
      );
    };

    const hasMagicPrefix = (binary, magic) => {
      if (!Type.isBinary(binary)) return false;

      Bitstring.maybeSetBytesFromText(binary);

      if (binary.bytes.length < magic.length) return false;

      return [...magic].every(
        (char, index) => binary.bytes[index] === char.charCodeAt(0),
      );
    };

    if (!Type.isRecordTuple(exportedPattern, "re_exported_pattern", 5)) {
      raiseNotExported();
    }

    const [_tag, header, source, options, code] = exportedPattern.data;

    // The header and code blobs carry PCRE2-native serialization the client
    // can't execute - the pattern is recompiled from source and options
    // instead, so blob validation is limited to the serialization magic
    // bytes ("re-PCRE2" and "S2RP") and the header size.
    if (
      !hasMagicPrefix(header, "re-PCRE2") ||
      header.bytes.length < 14 ||
      !hasMagicPrefix(code, "S2RP")
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
    const raiseBadarg = () => {
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "inspect",
        [compiledPattern, item],
        "erl_stdlib_errors",
      );
    };

    const registryEntry =
      ERTS.regexPatternRegistry.lookupByTerm(compiledPattern);

    if (registryEntry === null) {
      raiseBadarg();
    }

    if (!Interpreter.isStrictlyEqual(item, Type.atom("namelist"))) {
      raiseBadarg();
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
  "run/2": (subject, pattern) => {
    try {
      return Erlang_Re["run/3"](subject, pattern, Type.list());
    } catch (error) {
      // Errors with error_info re-raise with this function's own identity -
      // the BEAM reports the called BIF's frame with the caller's args.
      // Char data conversion failures without error_info pass through
      // unchanged: on the server they raise from OTP's urun wrapper, which
      // keeps the run/3 frame with the defaulted options.
      if (error.struct && error.stacktrace[0]?.errorInfo) {
        Interpreter.raiseBifError(
          "badarg",
          "re",
          "run",
          [subject, pattern],
          "erl_stdlib_errors",
        );
      }

      throw error;
    }
  },
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
    // range of a 32-bit integer.
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

    const buildPatternEntry = (compiled) => ({
      anchored: acc.anchored,
      compiled: compiled,
      firstline: acc.firstline,
      unicode: compiled.opts.unicode === true,
    });

    const isBoundedInteger = (term) =>
      Type.isInteger(term) && term.value >= 0n && term.value <= MAX_INT32;

    // Validates the capture option and returns the capture kind, targets
    // and type.
    const parseCaptureSpec = () => {
      let captureKind = "all";
      let captureTargets = null;
      let captureType = "index";

      if (captureOption !== null) {
        if (captureOption.data.length === 3) {
          const typeTerm = captureOption.data[2];

          if (
            !Type.isAtom(typeTerm) ||
            !CAPTURE_TYPE_ATOMS.has(typeTerm.value)
          ) {
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
              const name = ERTS.regex.charDataToText(element);

              if (name === null) raiseArgumentError();

              return {name};
            }

            raiseArgumentError();
          });
        } else {
          raiseArgumentError();
        }
      }

      return {captureKind, captureTargets, captureType};
    };

    // Parses the :re.run options list. Later occurrences win for the capture,
    // offset and limit options. optionsValid turns false on the first invalid
    // option.
    const parseRunOptions = () => {
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

      if (optionsValid) {
        for (const option of options.data) {
          if (Type.isAtom(option) && option.value === "global") {
            isGlobal = true;
            continue;
          }

          if (
            Type.isAtom(option) &&
            Object.hasOwn(RUN_FLAG_KEYS, option.value)
          ) {
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

      return {
        acc,
        captureOption,
        compileOnlyOptionUsed,
        dualOptionUsed,
        isGlobal,
        limitOptions,
        notImplementedOption,
        offsetOption,
        optionsValid,
        runFlags,
      };
    };

    // Used where validation has already passed for the subject and pattern
    // and no badopt cause applies, so the formatter derives no bullets and
    // the message stays the plain "argument error".
    const raiseArgumentError = () => {
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "run",
        [subject, pattern, options],
        "erl_stdlib_errors",
      );
    };

    // Char data conversion failures mirror the server's split: a binary
    // term fails inside the BIF, which raises with stdlib error_info,
    // while any other term fails inside OTP's urun wrapper, whose frame
    // carries no error_info.
    const raiseCharDataError = (term) => {
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "run",
        [subject, pattern, options],
        Type.isBitstring(term) ? "erl_stdlib_errors" : null,
      );
    };

    const raiseNotImplemented = (option) => {
      throw new HologramInterpreterError(
        `the ${Interpreter.inspect(option)} option is not yet implemented in Hologram`,
      );
    };

    // Resolves the offset option to a JS string start position. The offset
    // is a byte offset into the subject. An offset inside a character
    // raises, and an offset beyond the subject raises in a non-global run
    // while a global run returns null, which reports no match found.
    const resolveStartPosition = () => {
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

        if (offsetBeyondSubject) {
          if (isGlobal) return null;

          raiseArgumentError();
        }
      }

      return startPosition;
    };

    // Shapes match results into the :re.run return term, applying the
    // capture spec.
    const shapeMatchResults = (matchResults) => {
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
              : Bitstring.fromBytes(
                  [...slice].map((char) => char.charCodeAt(0)),
                );
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
    };

    // --- Options ---

    const {
      acc,
      captureOption,
      compileOnlyOptionUsed,
      dualOptionUsed,
      isGlobal,
      limitOptions,
      notImplementedOption,
      offsetOption,
      optionsValid,
      runFlags,
    } = parseRunOptions();

    // --- Pattern (validation phase) ---

    const registryEntry = ERTS.regexPatternRegistry.lookupByTerm(pattern);

    let entry = null;
    let patternInvalid = false;
    let patternRaisesArgumentError = false;

    if (registryEntry !== null) {
      entry = registryEntry;
    } else if (acc.unicodeOption) {
      // In unicode mode only the pattern term shape is validated here.
      // The pattern resolves later, as char data conversion failures raise
      // from the resolution phase instead of contributing a bullet.
      if (!Type.isBinary(pattern) && !Type.isList(pattern)) {
        patternInvalid = true;
      }
    } else {
      // In byte mode the pattern resolves during validation
      let patternBinary = null;

      try {
        patternBinary = Erlang["iolist_to_binary/1"](pattern);
      } catch {
        patternInvalid = true;
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
            patternInvalid = true;
          }
        } else {
          entry = buildPatternEntry(result);
        }
      }
    }

    // --- Subject (validation phase) ---

    // The subject is validated as iodata unless it is consumed as char data,
    // which happens with the unicode option or a unicode compiled pattern
    const byteModeSubject =
      !acc.unicodeOption && !(registryEntry !== null && registryEntry.unicode);

    let subjectBinary = null;
    let subjectInvalid = false;

    if (byteModeSubject) {
      try {
        subjectBinary = Erlang["iolist_to_binary/1"](subject);
      } catch {
        subjectInvalid = true;
      }
    }

    // --- Combined validation errors ---

    // The formatter recomputes the per-argument bullets from the frame
    // args, like the server's must_be_iodata and must_be_regexp probes do.
    if (subjectInvalid || patternInvalid || !optionsValid) {
      Interpreter.raiseBifError(
        "badarg",
        "re",
        "run",
        [subject, pattern, options],
        "erl_stdlib_errors",
        optionsValid ? null : "badopt",
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

      if (subjectText === null) raiseCharDataError(subject);

      const patternText = ERTS.regex.charDataToText(pattern);

      if (patternText === null) raiseCharDataError(pattern);

      // The option clash raises instead of returning a compile error tuple
      if (acc.engineOpts.never_utf) raiseArgumentError();

      const result = ERTS.regex.compileText(patternText, acc.engineOpts);

      // The formatter recomputes the parse-error bullet by compiling the
      // pattern with default options, like the server's must_be_regexp
      // probe does.
      if (result.error) {
        Interpreter.raiseBifError(
          "badarg",
          "re",
          "run",
          [subject, pattern, options],
          "erl_stdlib_errors",
        );
      }

      entry = buildPatternEntry(result);
    }

    // --- Capture spec (validation phase) ---

    // The spec content is validated before matching, so an invalid spec
    // raises even when the subject wouldn't match
    const {captureKind, captureTargets, captureType} = parseCaptureSpec();

    // --- Options not yet supported ---

    if (notImplementedOption !== null) {
      raiseNotImplemented(notImplementedOption);
    }

    // --- Subject resolution ---

    if (subjectText === null) {
      if (entry.unicode) {
        subjectText = ERTS.regex.charDataToText(subject);

        if (subjectText === null) raiseCharDataError(subject);
      } else {
        Bitstring.maybeSetBytesFromText(subjectBinary);
        subjectText = ERTS.regex.textFromLatin1Bytes(subjectBinary.bytes);
      }
    }

    // --- Start position ---

    const startPosition = resolveStartPosition();

    if (startPosition === null) return Type.atom("nomatch");

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

    return shapeMatchResults(matchResults);
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
