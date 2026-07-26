"use strict";

import Bitstring from "../bitstring.mjs";
import Erlang from "./erlang.mjs";
import ERTS from "../erts.mjs";
import HologramInterpreterError from "../errors/interpreter_error.mjs";
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
        if (RegexEngine.parseCompileOption(option, acc) === "invalid") {
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
        patternText = RegexEngine.charDataToText(pattern);
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

  // Start run/3
  "run/3": (subject, pattern, options) => {
    // Run-only option atoms not yet supported.
    // TODO: implement the global, notbol, noteol, notempty, notempty_atstart
    // and report_errors run options.
    const RUN_ONLY_ATOMS = new Set([
      "global",
      "notbol",
      "noteol",
      "notempty",
      "notempty_atstart",
      "report_errors",
    ]);

    // Run-only tuple option tags not yet supported.
    // TODO: implement the capture, offset, match_limit and
    // match_limit_recursion run options.
    const RUN_ONLY_TUPLE_TAGS = new Set([
      "capture",
      "match_limit",
      "match_limit_recursion",
      "offset",
    ]);

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

    let compileOnlyOptionUsed = false;
    let notImplementedOption = null;
    let optionsValid = Type.isProperList(options);
    let recompileOption = null;

    if (optionsValid) {
      for (const option of options.data) {
        const isRunOnly =
          (Type.isAtom(option) && RUN_ONLY_ATOMS.has(option.value)) ||
          (Type.isTuple(option) &&
            (option.data.length === 2 || option.data.length === 3) &&
            Type.isAtom(option.data[0]) &&
            RUN_ONLY_TUPLE_TAGS.has(option.data[0].value));

        if (isRunOnly) {
          notImplementedOption ??= option;
          continue;
        }

        switch (RegexEngine.parseCompileOption(option, acc)) {
          case "compile":
            compileOnlyOptionUsed = true;
            break;

          case "dual":
            recompileOption = option;
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

        const result = RegexEngine.compileBytes(
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

    // Compile options don't apply to an already compiled pattern
    if (
      registryEntry !== null &&
      (compileOnlyOptionUsed || acc.unicodeOption)
    ) {
      raiseArgumentError();
    }

    // --- Pattern (unicode resolution phase) ---

    let subjectText = null;

    if (entry === null) {
      acc.engineOpts.unicode = true;

      // The subject char data converts before the pattern compiles
      subjectText = RegexEngine.charDataToText(subject);

      const patternText = RegexEngine.charDataToText(pattern);

      // The option clash raises instead of returning a compile error tuple
      if (acc.engineOpts.never_utf) raiseArgumentError();

      const result = RegexEngine.compile(patternText, acc.engineOpts);

      if (result.error) {
        // Error positions are byte offsets in the pattern
        const position = RegexEngine.utf16IndexToByteOffset(
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

    // --- Options not yet supported ---

    if (notImplementedOption !== null) {
      raiseNotImplemented(notImplementedOption);
    }

    // TODO: implement re-routing of newline and bsr run options through the
    // stored AST of an already compiled pattern.
    if (registryEntry !== null && recompileOption !== null) {
      raiseNotImplemented(recompileOption);
    }

    // TODO: implement firstline matching semantics.
    if (entry.firstline) {
      raiseNotImplemented(Type.atom("firstline"));
    }

    // --- Subject resolution ---

    if (subjectText === null) {
      if (entry.unicode) {
        subjectText = RegexEngine.charDataToText(subject);
      } else {
        Bitstring.maybeSetBytesFromText(subjectBinary);
        subjectText = RegexEngine.textFromLatin1Bytes(subjectBinary.bytes);
      }
    }

    // --- Match ---

    const matchResult = RegexEngine.match(entry.compiled, subjectText, {
      anchored: entry.anchored || acc.anchored,
      startPosition: 0,
    });

    if (matchResult === null) return Type.atom("nomatch");

    // --- Captures (index type) ---

    // In byte mode JS string indices are byte offsets already
    const toByteOffset = entry.unicode
      ? (index) => RegexEngine.utf16IndexToByteOffset(subjectText, index)
      : (index) => index;

    const groupTuples = [];

    for (let number = 1; number <= entry.compiled.groupMap.count; number++) {
      const capture = matchResult.captures[number];

      if (capture === null) {
        groupTuples.push(Type.tuple([Type.integer(-1), Type.integer(0)]));
      } else {
        const start = toByteOffset(capture.start);
        const end = toByteOffset(capture.end);

        groupTuples.push(
          Type.tuple([Type.integer(start), Type.integer(end - start)]),
        );
      }
    }

    // Trailing unset groups are not reported
    while (
      groupTuples.length > 0 &&
      groupTuples[groupTuples.length - 1].data[0].value === -1n
    ) {
      groupTuples.pop();
    }

    const matchStart = toByteOffset(matchResult.start);
    const matchEnd = toByteOffset(matchResult.end);

    const capturedTuples = [
      Type.tuple([
        Type.integer(matchStart),
        Type.integer(matchEnd - matchStart),
      ]),
      ...groupTuples,
    ];

    return Type.tuple([Type.atom("match"), Type.list(capturedTuples)]);
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
