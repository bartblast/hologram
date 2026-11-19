"use strict";

import Bitstring from "../../bitstring.mjs";
import ERTS from "../../erts.mjs";
import RegexAnalyzer from "./regex_analyzer.mjs";
import RegexInterpreter from "./regex_interpreter.mjs";

import {
  newlineLengthAt,
  NEWLINE_PAIR_CONVENTIONS,
  NEWLINE_VERBS,
} from "./regex_newlines.mjs";

import {startOptionSettings} from "./regex_options.mjs";
import RegexOffsetMap from "./regex_offset_map.mjs";
import RegexParseError from "./regex_parse_error.mjs";
import RegexParser, {scanStartOptions} from "./regex_parser.mjs";
import RegexTranslator from "./regex_translator.mjs";
import Type from "../../type.mjs";

// Compile option atoms passed to the engine under the same name.
const ENGINE_OPT_ATOMS = new Set([
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

const NEWLINE_TYPES = new Set(Object.values(NEWLINE_VERBS));

// Subjects below this byte size aren't cached: converting them costs less
// than the cache lookup and store. Measured in Node 24 and Chrome.
const CACHED_SUBJECT_MIN_BYTE_SIZE = 64;

// Facade over the regex machinery: compiles PCRE2 patterns into matchable
// entries and matches them against JS strings, hiding the native/interpreted
// engine split. Also bridges boxed Erlang terms to engine inputs: char data
// conversion and :re compile option parsing.
export default class RegexEngine {
  // Converted texts of binary subjects, by binary, one map per mode, since
  // the texts of one binary differ between the modes, and the offset maps of
  // their unicode mode texts. Each lives as long as its binary.
  static #latin1SubjectTexts = new WeakMap();
  static #subjectOffsetMaps = new WeakMap();
  static #utf8SubjectTexts = new WeakMap();

  // Keeps a leading byte order mark, which is data in a binary, where
  // ERTS.utf8Decoder drops it.
  static #utf8Decoder = new TextDecoder("utf-8", {
    fatal: true,
    ignoreBOM: true,
  });

  // Converts char data (a binary or a possibly nested list of code points
  // and binaries, with an improper binary tail allowed) to a JS string,
  // decoding binaries from UTF-8. Returns null on any failure, leaving the
  // raise (with the caller's own identity) to the caller.
  static charDataToText(charData) {
    if (Type.isBitstring(charData)) return $.#textFromBinaryCharData(charData);
    if (Type.isList(charData)) return $.#textFromListCharData(charData);

    return null;
  }

  // Compares two JS strings by the byte order of their UTF-8 encodings,
  // usable directly as an Array sort comparator. Differs from the default
  // JS string order, which compares UTF-16 units and sorts astral code
  // points before some BMP ones.
  static compareByUtf8Bytes(text1, text2) {
    const bytes1 = ERTS.utf8Encoder.encode(text1);
    const bytes2 = ERTS.utf8Encoder.encode(text2);
    const minLength = Math.min(bytes1.length, bytes2.length);

    for (let index = 0; index < minLength; index++) {
      if (bytes1[index] !== bytes2[index]) {
        return bytes1[index] - bytes2[index];
      }
    }

    return bytes1.length - bytes2.length;
  }

  // Compiles a PCRE2 pattern source into a matchable entry, routed to the
  // native JS RegExp engine when every construct translates with identical
  // semantics, and to the interpreter otherwise.
  // Returns {error: {message, position}} when the pattern is not valid
  // PCRE2 syntax.
  static compile(source, opts = {}) {
    try {
      return $.#compileValid(source, opts);
    } catch (error) {
      if (error instanceof RegexParseError) {
        return {error: {message: error.message, position: error.position}};
      }

      throw error;
    }
  }

  // Compiles a PCRE2 pattern from its bytes: UTF-8 when opts.unicode is set
  // and latin-1 otherwise, switching to UTF-8 when the pattern enables UTF
  // mode with a start option verb - unless UTF is disabled, then parsing
  // raises the disabled error at the verb. Error positions are byte offsets.
  static compileBytes(bytes, opts) {
    let effectiveOpts = opts;
    let source;

    if (opts.unicode === true) {
      const decoded = $.decodeUtf8(bytes);

      if (decoded.error) return decoded;

      source = decoded.text;
    } else {
      source = $.textFromLatin1Bytes(bytes);

      if (opts.never_utf !== true && $.hasUtfStartOption(source)) {
        const decoded = $.decodeUtf8(bytes);

        if (decoded.error) return decoded;

        source = decoded.text;
        effectiveOpts = {...opts, unicode: true};
      }
    }

    // In latin-1 source the JS string indices are byte offsets already
    return effectiveOpts.unicode === true
      ? $.compileText(source, effectiveOpts)
      : $.compile(source, effectiveOpts);
  }

  // Compiles a PCRE2 pattern from a JS string, converting error positions
  // from UTF-16 indices to UTF-8 byte offsets. PCRE2 reports some errors at
  // a position past the end of the pattern, and each unit past the end counts
  // as one byte.
  static compileText(text, opts) {
    const compiled = $.compile(text, opts);

    if (compiled.error) {
      const offsetMap = new RegexOffsetMap(text, null);
      const position = compiled.error.position;

      const byteOffset =
        position > text.length
          ? offsetMap.byteLength() + position - text.length
          : offsetMap.toByteOffset(position);

      return {
        error: {message: compiled.error.message, position: byteOffset},
      };
    }

    return compiled;
  }

  // Decodes UTF-8 bytes to a JS string, validating with PCRE2 semantics.
  // Returns {text} on success and {error: {message, position}} on invalid
  // input, with the position at the first byte of the invalid character
  // and the message matching PCRE2's UTF-8 error texts.
  static decodeUtf8(bytes) {
    try {
      return {text: $.#utf8Decoder.decode(bytes)};
    } catch {
      // The native decoder rejects exactly what PCRE2 rejects, but reports
      // neither PCRE2's message nor the position
      return $.#utf8ErrorOf(bytes);
    }
  }

  // Reports whether the pattern source enables UTF mode with a (*UTF) or
  // (*UTF8) verb within the start-of-pattern option settings. Scans without
  // a full parse, because byte input must be rerouted to UTF-8 decoding
  // before the pattern is parsed.
  static hasUtfStartOption(source) {
    for (const {name} of scanStartOptions(source)) {
      if (name === "UTF" || name === "UTF8") return true;
    }

    return false;
  }

  // Matches a compiled entry against a subject string, scanning forward from
  // the start position, or only at the start position when anchored.
  // Returns {start, end, captures} with PCRE2 group numbering, or null.
  // Positions are JS string indices.
  //
  // Supported scan flags in runOpts: firstline restricts where a match
  // attempt may start (at or before the first newline that follows the
  // start position), notbol and noteol make the subject boundaries not
  // count as line boundaries, and notempty/notemptyAtStart reject empty
  // matches (everywhere or at the start position only). matchLimit and
  // matchLimitRecursion bound the matching work, with an exceeded limit
  // reported as no match - a limit verb in the pattern wins when lower.
  //
  // runOpts.firstNewlinePosition, when given with firstline, is the first
  // newline position at or after the start position (Infinity when there is
  // none), already looked up by matchGlobal() so its attempts don't each
  // scan for it again. runOpts.subjectCache goes to the interpreter, which
  // keeps data derived from the subject in it, so matchGlobal() passes one
  // cache to all its attempts.
  static match(compiled, subject, runOpts = {}) {
    const anchored = runOpts.anchored === true;
    const startPosition = runOpts.startPosition ?? 0;

    const maxStartPosition =
      runOpts.firstline === true
        ? (runOpts.firstNewlinePosition ??
          $.#firstNewlinePosition(compiled.newlineType, subject, startPosition))
        : Infinity;

    // The scan flags and limits need match-time decisions a JS regexp can't
    // express, so runs with them take the interpreter route
    const needsInterpreter =
      runOpts.matchLimit !== undefined ||
      runOpts.matchLimitRecursion !== undefined ||
      runOpts.notbol === true ||
      runOpts.noteol === true ||
      runOpts.notempty === true ||
      runOpts.notemptyAtStart === true;

    if (compiled.strategy === "native" && !needsInterpreter) {
      const regexp = anchored ? $.#stickyRegexp(compiled) : compiled.regexp;

      regexp.lastIndex = startPosition;

      const jsMatch = regexp.exec(subject);

      if (jsMatch === null) return null;

      // Without \K on the native route the reported match start is also the
      // attempt start
      if (jsMatch.indices[0][0] > maxStartPosition) return null;

      const captures = [null];

      for (let number = 1; number <= compiled.groupMap.count; number++) {
        const jsNumber = compiled.groupMapping.get(number);
        const indices = jsMatch.indices[jsNumber];

        captures.push(
          indices === undefined ? null : {start: indices[0], end: indices[1]},
        );
      }

      return {
        start: jsMatch.indices[0][0],
        end: jsMatch.indices[0][1],
        captures: captures,
      };
    }

    return RegexInterpreter.match(compiled.ast, subject, {
      ...compiled.opts,
      anchored: anchored,
      groupMap: compiled.groupMap,
      matchLimit: runOpts.matchLimit,
      matchLimitRecursion: runOpts.matchLimitRecursion,
      maxStartPosition: maxStartPosition,
      notbol: runOpts.notbol === true,
      notempty: runOpts.notempty === true,
      notemptyAtStart: runOpts.notemptyAtStart === true,
      noteol: runOpts.noteol === true,
      startOptionSettings: compiled.startOptionSettings,
      startPosition: startPosition,
      subjectCache: runOpts.subjectCache,
      subroutines: $.#subroutines(compiled),
    });
  }

  // Matches a compiled entry repeatedly with PCRE global scan semantics:
  // each attempt continues at the previous match end, and after an empty
  // match the same position is retried anchored with another empty match
  // rejected - a successful retry counts as an additional match, a failed
  // one advances the scan by one character (a CRLF pair when the newline
  // convention treats it as one newline, a surrogate pair in unicode mode).
  // Returns an array of match results, empty when there is no match.
  // Scan flags in runOpts apply to every attempt.
  static matchGlobal(compiled, subject, runOpts = {}) {
    const results = [];
    let position = runOpts.startPosition ?? 0;

    // With firstline, the first newline at or after an attempt position is
    // kept and looked up again only once an attempt starts past it. A kept
    // newline at or after the new position is still the first one, since
    // the earlier lookup found no newline before it.
    let firstNewlinePosition = -1;

    // One subject cache for all attempts, so the interpreter derives data
    // from the subject once per run instead of once per attempt
    const subjectCache = {graphemeSegments: null};

    const attemptOpts = (startPosition, extraOpts = {}) => {
      const opts = {
        ...runOpts,
        ...extraOpts,
        startPosition: startPosition,
        subjectCache: subjectCache,
      };

      if (runOpts.firstline === true) {
        if (firstNewlinePosition < startPosition) {
          firstNewlinePosition = $.#firstNewlinePosition(
            compiled.newlineType,
            subject,
            startPosition,
          );
        }

        opts.firstNewlinePosition = firstNewlinePosition;
      }

      return opts;
    };

    while (position <= subject.length) {
      const result = $.match(compiled, subject, attemptOpts(position));

      if (result === null) break;

      results.push(result);

      if (result.end > result.start) {
        position = result.end;
        continue;
      }

      // With \K the reported start can be past the kept newline, so the
      // retry checks the kept newline against its own start too
      const retry = $.match(
        compiled,
        subject,
        attemptOpts(result.start, {anchored: true, notemptyAtStart: true}),
      );

      if (retry !== null) {
        results.push(retry);
        position = retry.end;
      } else {
        position =
          result.start + $.#scanAdvance(compiled, subject, result.start);
      }
    }

    return results;
  }

  // Applies a :re compile option to the accumulator and returns the option
  // kind: "anchored", "compile" (compile-only), "dual" (also a run option),
  // or "invalid".
  static parseCompileOption(option, acc) {
    if (Type.isAtom(option)) {
      if (ENGINE_OPT_ATOMS.has(option.value)) {
        acc.engineOpts[option.value] = true;
        return "compile";
      }

      switch (option.value) {
        case "anchored":
          acc.anchored = true;
          return "anchored";

        case "bsr_anycrlf":
          acc.engineOpts.bsr_anycrlf = true;
          return "dual";

        case "bsr_unicode":
          acc.engineOpts.bsr_anycrlf = false;
          return "dual";

        case "firstline":
          acc.firstline = true;
          return "compile";

        case "no_start_optimize":
          return "compile";

        case "unicode":
          acc.unicodeOption = true;
          return "compile";

        default:
          return "invalid";
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
      return "dual";
    }

    return "invalid";
  }

  // Returns the offset map of a subject's unicode mode text. A binary subject
  // of CACHED_SUBJECT_MIN_BYTE_SIZE bytes and more keeps its map, so later
  // runs on it reuse the checkpoints laid down so far.
  static subjectOffsetMap(subject, text) {
    if (!Type.isBinary(subject)) return new RegexOffsetMap(text, null);

    Bitstring.maybeSetBytesFromText(subject);

    const byteLength = subject.bytes.length;

    if (byteLength < CACHED_SUBJECT_MIN_BYTE_SIZE) {
      return new RegexOffsetMap(text, byteLength);
    }

    let offsetMap = $.#subjectOffsetMaps.get(subject);

    if (offsetMap === undefined) {
      offsetMap = new RegexOffsetMap(text, byteLength);
      $.#subjectOffsetMaps.set(subject, offsetMap);
    }

    return offsetMap;
  }

  // Returns the text a binary subject is matched against: decoded from UTF-8
  // in unicode mode, or null when it isn't valid UTF-8, and one char per
  // byte otherwise. Converting the same binary again in the same mode
  // returns the kept text, for binaries of CACHED_SUBJECT_MIN_BYTE_SIZE
  // bytes and more.
  static subjectTextFromBinary(binary, unicode) {
    Bitstring.maybeSetBytesFromText(binary);

    if (binary.bytes.length < CACHED_SUBJECT_MIN_BYTE_SIZE) {
      return $.#subjectTextFromBytes(binary.bytes, unicode);
    }

    const texts = unicode ? $.#utf8SubjectTexts : $.#latin1SubjectTexts;
    const keptText = texts.get(binary);

    // A text is a string or null, so undefined means none is kept yet
    if (keptText !== undefined) return keptText;

    const text = $.#subjectTextFromBytes(binary.bytes, unicode);
    texts.set(binary, text);

    return text;
  }

  // Maps every byte to one JS char, so JS string indices are byte offsets
  // and matching is byte-faithful even for non-UTF-8 binaries.
  static textFromLatin1Bytes(bytes) {
    // ASCII bytes decode to the same chars, so the part before the first
    // byte above 0x7f decodes natively. There's no native Latin-1 decoder:
    // "latin1" in TextDecoder is windows-1252, which remaps 0x80-0x9f.
    const asciiLength = $.#asciiPrefixLength(bytes);
    let text = $.#utf8Decoder.decode(bytes.subarray(0, asciiLength));

    // Chunked to stay within the argument count limit of fromCharCode()
    for (let start = asciiLength; start < bytes.length; start += 4096) {
      text += String.fromCharCode.apply(
        null,
        bytes.subarray(start, start + 4096),
      );
    }

    return text;
  }

  // Returns true when the newline convention treats CR LF as one newline.
  static usesCrlf(newlineType) {
    return NEWLINE_PAIR_CONVENTIONS.has(newlineType);
  }

  // Returns how many bytes at the start are below 0x80.
  static #asciiPrefixLength(bytes) {
    for (let index = 0; index < bytes.length; index++) {
      if (bytes[index] > 0x7f) return index;
    }

    return bytes.length;
  }

  static #compileValid(source, opts) {
    const ast = RegexParser.parse(source, opts);
    const groupMap = RegexAnalyzer.buildGroupMap(ast);
    const settings = startOptionSettings(ast);
    const strategy = RegexAnalyzer.route(ast, groupMap, opts);

    const compiled = {
      ast: ast,
      groupMap: groupMap,
      groupMapping: null,
      newlineType: settings.newline ?? opts.newline ?? "lf",
      opts: opts,
      regexp: null,
      regexpSticky: null,
      source: source,
      startOptionSettings: settings,
      strategy: strategy,
      subroutines: null,
    };

    if (strategy === "native") {
      const translated = RegexTranslator.translate(ast, opts);

      // The d flag provides match indices, the g flag makes lastIndex control
      // the match start position
      compiled.groupMapping = translated.groupMapping;
      compiled.regexp = new RegExp(translated.source, `${translated.flags}dg`);
    }

    return compiled;
  }

  // Returns the position where the first newline sequence at or after the
  // given position starts, or Infinity when there is none.
  static #firstNewlinePosition(newlineType, subject, fromPosition) {
    for (let position = fromPosition; position < subject.length; position++) {
      if (newlineLengthAt(newlineType, subject, position) > 0) return position;
    }

    return Infinity;
  }

  // Returns how many UTF-16 units the global scan advances over the
  // character at the position.
  static #scanAdvance(compiled, subject, position) {
    const newlineLength = newlineLengthAt(
      compiled.newlineType,
      subject,
      position,
    );

    if (newlineLength === 2) return 2;

    if (
      compiled.opts.unicode === true &&
      subject.codePointAt(position) > 0xffff
    ) {
      return 2;
    }

    return 1;
  }

  // The y flag makes the match start exactly at lastIndex instead of
  // scanning forward from it. Built lazily, as most patterns are never
  // matched anchored.
  static #stickyRegexp(compiled) {
    if (compiled.regexpSticky === null) {
      compiled.regexpSticky = new RegExp(
        compiled.regexp.source,
        compiled.regexp.flags.replace("g", "y"),
      );
    }

    return compiled.regexpSticky;
  }

  static #subjectTextFromBytes(bytes, unicode) {
    if (!unicode) return $.textFromLatin1Bytes(bytes);

    const decoded = $.decodeUtf8(bytes);

    return decoded.error ? null : decoded.text;
  }

  // The interpreter's subroutine table, built on first use, as patterns on
  // the native route rarely reach the interpreter.
  static #subroutines(compiled) {
    if (compiled.subroutines === null) {
      compiled.subroutines = RegexInterpreter.buildSubroutineTable(
        compiled.ast,
      );
    }

    return compiled.subroutines;
  }

  static #textFromBinaryCharData(binary) {
    if (!Type.isBinary(binary)) {
      return null;
    }

    Bitstring.maybeSetBytesFromText(binary);

    const decoded = $.decodeUtf8(binary.bytes);

    return decoded.error ? null : decoded.text;
  }

  static #textFromListCharData(list) {
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
          return null;
        }

        text += String.fromCodePoint(codePoint);
      } else if (Type.isBitstring(element)) {
        const elementText = $.#textFromBinaryCharData(element);

        if (elementText === null) {
          return null;
        }

        text += elementText;
      } else if (Type.isList(element)) {
        const elementText = $.#textFromListCharData(element);

        if (elementText === null) {
          return null;
        }

        text += elementText;
      } else {
        return null;
      }
    }

    if (!isProper) {
      const tail = list.data[list.data.length - 1];

      if (!Type.isBitstring(tail)) {
        return null;
      }

      const tailText = $.#textFromBinaryCharData(tail);

      if (tailText === null) {
        return null;
      }

      text += tailText;
    }

    return text;
  }

  static #utf8Error(detail, position) {
    return {error: {message: `UTF-8 error: ${detail}`, position: position}};
  }

  // Returns the PCRE2 UTF-8 error of bytes that aren't valid UTF-8, as
  // decodeUtf8() reports it.
  static #utf8ErrorOf(bytes) {
    const length = bytes.length;
    let index = 0;

    while (index < length) {
      const first = bytes[index];

      if (first < 0x80) {
        index++;
        continue;
      }

      if (first < 0xc0) {
        return $.#utf8Error("isolated byte with 0x80 bit set", index);
      }

      if (first >= 0xfe) {
        return $.#utf8Error("illegal byte (0xfe or 0xff)", index);
      }

      let additionalByteCount;

      if (first < 0xe0) additionalByteCount = 1;
      else if (first < 0xf0) additionalByteCount = 2;
      else if (first < 0xf8) additionalByteCount = 3;
      else if (first < 0xfc) additionalByteCount = 4;
      else additionalByteCount = 5;

      const remaining = length - index - 1;

      if (remaining < additionalByteCount) {
        const missing = additionalByteCount - remaining;
        const noun = missing === 1 ? "byte" : "bytes";
        return $.#utf8Error(`${missing} ${noun} missing at end`, index);
      }

      for (let offset = 1; offset <= additionalByteCount; offset++) {
        if ((bytes[index + offset] & 0xc0) !== 0x80) {
          return $.#utf8Error(`byte ${offset + 1} top bits not 0x80`, index);
        }
      }

      const second = bytes[index + 1];

      switch (additionalByteCount) {
        case 1:
          if ((first & 0x3e) === 0) {
            return $.#utf8Error("overlong 2-byte sequence", index);
          }
          break;

        case 2:
          if (first === 0xe0 && (second & 0x20) === 0) {
            return $.#utf8Error("overlong 3-byte sequence", index);
          }

          if (first === 0xed && second >= 0xa0) {
            return $.#utf8Error(
              "code points 0xd800-0xdfff are not defined",
              index,
            );
          }
          break;

        case 3:
          if (first === 0xf0 && (second & 0x30) === 0) {
            return $.#utf8Error("overlong 4-byte sequence", index);
          }

          if (first > 0xf4 || (first === 0xf4 && second > 0x8f)) {
            return $.#utf8Error(
              "code points greater than 0x10ffff are not defined",
              index,
            );
          }
          break;

        case 4:
          if (first === 0xf8 && (second & 0x38) === 0) {
            return $.#utf8Error("overlong 5-byte sequence", index);
          }
          return $.#utf8Error(
            "5-byte character is not allowed (RFC 3629)",
            index,
          );

        case 5:
          if (first === 0xfc && (second & 0x3c) === 0) {
            return $.#utf8Error("overlong 6-byte sequence", index);
          }
          return $.#utf8Error(
            "6-byte character is not allowed (RFC 3629)",
            index,
          );
      }

      index += additionalByteCount + 1;
    }

    // Unreachable as long as the native decoder rejects only what this scan
    // rejects
    throw new Error("UTF-8 bytes rejected by the native decoder are valid");
  }
}

const $ = RegexEngine;
