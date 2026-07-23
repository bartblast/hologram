"use strict";

export default class RegexUtils {
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
}

const $ = RegexUtils;
