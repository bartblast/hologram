"use strict";

import RegexAnalyzer from "./regex_analyzer.mjs";
import RegexInterpreter from "./regex_interpreter.mjs";
import RegexParseError from "./regex_parse_error.mjs";
import RegexParser from "./regex_parser.mjs";
import RegexTranslator from "./regex_translator.mjs";

// Facade over the regex machinery: compiles PCRE2 patterns into matchable
// entries and matches them against JS strings, hiding the native/interpreted
// engine split. Byte-level subject encoding and Erlang term shaping are the
// callers' concern.
export default class RegexEngine {
  // Converts a UTF-8 byte offset to a JS string index.
  static byteOffsetToUtf16Index(text, byteOffset) {
    let currentByteOffset = 0;
    let utf16Index = 0;

    while (currentByteOffset < byteOffset && utf16Index < text.length) {
      const codePoint = text.codePointAt(utf16Index);
      currentByteOffset += $.#calculateCodePointByteCount(codePoint);
      utf16Index += codePoint > 0xffff ? 2 : 1;
    }

    return utf16Index;
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

  // Decodes UTF-8 bytes to a JS string, validating with PCRE2 semantics.
  // Returns {text} on success and {error: {message, position}} on invalid
  // input, with the position at the first byte of the invalid character
  // and the message matching PCRE2's UTF-8 error texts.
  static decodeUtf8(bytes) {
    const codePoints = [];
    const length = bytes.length;
    let index = 0;

    while (index < length) {
      const first = bytes[index];

      if (first < 0x80) {
        codePoints.push(first);
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

      let codePoint = first & (0x3f >> additionalByteCount);

      for (let offset = 1; offset <= additionalByteCount; offset++) {
        codePoint = (codePoint << 6) | (bytes[index + offset] & 0x3f);
      }

      codePoints.push(codePoint);
      index += additionalByteCount + 1;
    }

    let text = "";

    // Chunked to stay within the argument count limit of fromCodePoint()
    for (let start = 0; start < codePoints.length; start += 4096) {
      text += String.fromCodePoint(...codePoints.slice(start, start + 4096));
    }

    return {text: text};
  }

  // Matches a compiled entry against a subject string, scanning forward from
  // the start position. Returns {start, end, captures} with PCRE2 group
  // numbering, or null. Positions are JS string indices.
  static match(compiled, subject, runOpts = {}) {
    const startPosition = runOpts.startPosition ?? 0;

    if (compiled.strategy === "native") {
      compiled.regexp.lastIndex = startPosition;

      const jsMatch = compiled.regexp.exec(subject);

      if (jsMatch === null) return null;

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
      groupMap: compiled.groupMap,
      startPosition: startPosition,
    });
  }

  // Converts a JS string index to a UTF-8 byte offset.
  static utf16IndexToByteOffset(text, utf16Index) {
    let byteOffset = 0;

    for (let i = 0; i < utf16Index;) {
      const codePoint = text.codePointAt(i);
      byteOffset += $.#calculateCodePointByteCount(codePoint);
      i += codePoint > 0xffff ? 2 : 1;
    }

    return byteOffset;
  }

  static #calculateCodePointByteCount(codePoint) {
    // 1-byte: ASCII
    if (codePoint <= 0x7f) return 1;

    // 2-byte
    if (codePoint <= 0x7ff) return 2;

    // 3-byte
    if (codePoint <= 0xffff) return 3;

    // 4-byte
    return 4;
  }

  static #compileValid(source, opts) {
    const ast = RegexParser.parse(source, opts);
    const groupMap = RegexAnalyzer.buildGroupMap(ast);
    const strategy = RegexAnalyzer.route(ast, groupMap, opts);

    const compiled = {
      ast: ast,
      groupMap: groupMap,
      groupMapping: null,
      opts: opts,
      regexp: null,
      source: source,
      strategy: strategy,
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

  static #utf8Error(detail, position) {
    return {error: {message: `UTF-8 error: ${detail}`, position: position}};
  }
}

const $ = RegexEngine;
