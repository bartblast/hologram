"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// Erlang External Term Format (ETF) Decoder
// See: https://www.erlang.org/doc/apps/erts/erl_ext_dist.html

export default class EtfDecoder {
  // ETF tag constants
  static #SMALL_INTEGER_EXT = 97;
  static #INTEGER_EXT = 98;
  static #ATOM_EXT = 100;
  static #SMALL_TUPLE_EXT = 104;
  static #LARGE_TUPLE_EXT = 105;
  static #NIL_EXT = 106;
  static #STRING_EXT = 107;
  static #LIST_EXT = 108;
  static #BINARY_EXT = 109;
  static #SMALL_BIG_EXT = 110;
  static #LARGE_BIG_EXT = 111;
  static #SMALL_ATOM_EXT = 115;
  static #MAP_EXT = 116;
  static #ATOM_UTF8_EXT = 118;
  static #SMALL_ATOM_UTF8_EXT = 119;

  static decode(binary) {
    Bitstring.maybeSetBytesFromText(binary);

    const bytes = binary.bytes;
    const dataView = new DataView(
      bytes.buffer,
      bytes.byteOffset,
      bytes.byteLength,
    );

    // Check ETF version byte (must be 131)
    if (dataView.getUint8(0) !== 131) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "invalid external representation of a term",
        ),
      );
    }

    const result = $.#decodeTerm(dataView, bytes, 1);
    return result.term;
  }

  static #decodeTerm(dataView, bytes, offset) {
    if (offset >= bytes.length) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(
          1,
          "invalid external representation of a term",
        ),
      );
    }

    const tag = dataView.getUint8(offset);

    switch (tag) {
      case $.#SMALL_INTEGER_EXT:
        return $.#decodeSmallInteger(dataView, offset + 1);

      case $.#INTEGER_EXT:
        return $.#decodeInteger(dataView, offset + 1);

      case $.#SMALL_BIG_EXT:
        return $.#decodeSmallBig(dataView, bytes, offset + 1);

      case $.#LARGE_BIG_EXT:
        return $.#decodeLargeBig(dataView, bytes, offset + 1);

      case $.#ATOM_EXT:
        return $.#decodeAtom(dataView, bytes, offset + 1, false);

      case $.#SMALL_ATOM_EXT:
        return $.#decodeSmallAtom(dataView, bytes, offset + 1, false);

      case $.#ATOM_UTF8_EXT:
        return $.#decodeAtom(dataView, bytes, offset + 1, true);

      case $.#SMALL_ATOM_UTF8_EXT:
        return $.#decodeSmallAtom(dataView, bytes, offset + 1, true);

      case $.#BINARY_EXT:
        return $.#decodeBinary(dataView, bytes, offset + 1);

      case $.#SMALL_TUPLE_EXT:
        return $.#decodeSmallTuple(dataView, bytes, offset + 1);

      case $.#LARGE_TUPLE_EXT:
        return $.#decodeLargeTuple(dataView, bytes, offset + 1);

      case $.#NIL_EXT:
        return {term: Type.list(), newOffset: offset + 1};

      case $.#STRING_EXT:
        return $.#decodeString(dataView, bytes, offset + 1);

      case $.#LIST_EXT:
        return $.#decodeList(dataView, bytes, offset + 1);

      case $.#MAP_EXT:
        return $.#decodeMap(dataView, bytes, offset + 1);

      default:
        Interpreter.raiseArgumentError(
          `unsupported external term format tag: ${tag}`,
        );
    }
  }

  // Integer decoders

  static #decodeSmallInteger(dataView, offset) {
    const value = dataView.getUint8(offset);
    return {
      term: Type.integer(value),
      newOffset: offset + 1,
    };
  }

  static #decodeInteger(dataView, offset) {
    const value = dataView.getInt32(offset);
    return {
      term: Type.integer(value),
      newOffset: offset + 4,
    };
  }

  static #decodeSmallBig(dataView, bytes, offset) {
    const n = dataView.getUint8(offset);
    const sign = dataView.getUint8(offset + 1);

    let value = 0n;
    for (let i = 0; i < n; i++) {
      const byte = BigInt(bytes[offset + 2 + i]);
      value += byte << BigInt(i * 8);
    }

    if (sign === 1) {
      value = -value;
    }

    return {
      term: Type.integer(value),
      newOffset: offset + 2 + n,
    };
  }

  static #decodeLargeBig(dataView, bytes, offset) {
    const n = dataView.getUint32(offset);
    const sign = dataView.getUint8(offset + 4);

    let value = 0n;
    for (let i = 0; i < n; i++) {
      const byte = BigInt(bytes[offset + 5 + i]);
      value += byte << BigInt(i * 8);
    }

    if (sign === 1) {
      value = -value;
    }

    return {
      term: Type.integer(value),
      newOffset: offset + 5 + n,
    };
  }

  // Atom decoders

  static #decodeAtom(dataView, bytes, offset, isUtf8) {
    const length = dataView.getUint16(offset);
    const atomBytes = bytes.slice(offset + 2, offset + 2 + length);

    const decoder = new TextDecoder(isUtf8 ? "utf-8" : "latin1");
    const atomString = decoder.decode(atomBytes);

    return {
      term: Type.atom(atomString),
      newOffset: offset + 2 + length,
    };
  }

  static #decodeSmallAtom(dataView, bytes, offset, isUtf8) {
    const length = dataView.getUint8(offset);
    const atomBytes = bytes.slice(offset + 1, offset + 1 + length);

    const decoder = new TextDecoder(isUtf8 ? "utf-8" : "latin1");
    const atomString = decoder.decode(atomBytes);

    return {
      term: Type.atom(atomString),
      newOffset: offset + 1 + length,
    };
  }

  // Binary decoder

  static #decodeBinary(dataView, bytes, offset) {
    const length = dataView.getUint32(offset);
    const binaryBytes = bytes.slice(offset + 4, offset + 4 + length);

    return {
      term: Bitstring.fromBytes(new Uint8Array(binaryBytes)),
      newOffset: offset + 4 + length,
    };
  }

  // Tuple decoders

  static #decodeSmallTuple(dataView, bytes, offset) {
    const arity = dataView.getUint8(offset);
    const elements = [];
    let currentOffset = offset + 1;

    for (let i = 0; i < arity; i++) {
      const result = $.#decodeTerm(dataView, bytes, currentOffset);
      elements.push(result.term);
      currentOffset = result.newOffset;
    }

    return {
      term: Type.tuple(elements),
      newOffset: currentOffset,
    };
  }

  static #decodeLargeTuple(dataView, bytes, offset) {
    const arity = dataView.getUint32(offset);
    const elements = [];
    let currentOffset = offset + 4;

    for (let i = 0; i < arity; i++) {
      const result = $.#decodeTerm(dataView, bytes, currentOffset);
      elements.push(result.term);
      currentOffset = result.newOffset;
    }

    return {
      term: Type.tuple(elements),
      newOffset: currentOffset,
    };
  }

  // List decoders

  static #decodeString(dataView, bytes, offset) {
    const length = dataView.getUint16(offset);
    const elements = [];

    for (let i = 0; i < length; i++) {
      const byte = bytes[offset + 2 + i];
      elements.push(Type.integer(byte));
    }

    return {
      term: Type.list(elements),
      newOffset: offset + 2 + length,
    };
  }

  static #decodeList(dataView, bytes, offset) {
    const length = dataView.getUint32(offset);
    const elements = [];
    let currentOffset = offset + 4;

    for (let i = 0; i < length; i++) {
      const result = $.#decodeTerm(dataView, bytes, currentOffset);
      elements.push(result.term);
      currentOffset = result.newOffset;
    }

    // Decode the tail
    const tailResult = $.#decodeTerm(dataView, bytes, currentOffset);
    currentOffset = tailResult.newOffset;

    // If tail is NIL (empty list), it's a proper list
    if (Type.isList(tailResult.term) && tailResult.term.data.length === 0) {
      return {
        term: Type.list(elements),
        newOffset: currentOffset,
      };
    }

    // Otherwise, it's an improper list
    elements.push(tailResult.term);
    return {
      term: Type.improperList(elements),
      newOffset: currentOffset,
    };
  }

  // Map decoder

  static #decodeMap(dataView, bytes, offset) {
    const arity = dataView.getUint32(offset);
    const entries = [];
    let currentOffset = offset + 4;

    for (let i = 0; i < arity; i++) {
      const keyResult = $.#decodeTerm(dataView, bytes, currentOffset);
      const valueResult = $.#decodeTerm(dataView, bytes, keyResult.newOffset);

      entries.push([keyResult.term, valueResult.term]);
      currentOffset = valueResult.newOffset;
    }

    return {
      term: Type.map(entries),
      newOffset: currentOffset,
    };
  }
}

const $ = EtfDecoder;
