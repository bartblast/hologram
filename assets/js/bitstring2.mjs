"use strict";

import HologramInterpreterError from "./errors/interpreter_error.mjs";

export default class Bitstring2 {
  static concatSegments(segments) {
    if (
      segments.every(
        (segment) => segment.type === "utf8" || segment.type === "binary",
      )
    ) {
      const len = segments.length;
      let text = "";

      for (let i = 0; i < len; i++) {
        text += segments[i].value.value;
      }

      return {type: "bitstring", text, bytes: null, numLeftoverBits: 0};
    }
  }

  static floatSegmentToBytes(segment) {
    let value;
    if (segment.value.type === "float") {
      value = segment.value.value;
    } else {
      // integer
      value = Number(segment.value.value);
    }

    const isLittleEndian = $.#isLittleEndian(segment);

    const bitCount = $.#calculateBitCount(segment);
    const byteLength = bitCount / 8;
    const buffer = new ArrayBuffer(byteLength);
    const dataView = new DataView(buffer);

    if (bitCount === 64) {
      dataView.setFloat64(0, value, isLittleEndian);
    } else if (bitCount === 32) {
      dataView.setFloat32(0, value, isLittleEndian);
    } else {
      // TODO: implement when browsers widely support 16-bit floats
      // dataView.setFloat16(0, value, isLittleEndian);
      throw new HologramInterpreterError(
        "16-bit float bitstring segments are not yet implemented in Hologram",
      );
    }

    return new Uint8Array(buffer);
  }

  static fromBits(bits) {
    const length = bits.length;
    const byteCount = Math.ceil(length / 8);
    const numLeftoverBits = length % 8;
    const bytes = new Uint8Array(byteCount);

    // Process 8 bytes at a time when possible
    let byteIndex = 0;
    let bitIndex = 0;

    // Fast path for byte-aligned chunks
    while (bitIndex + 8 <= length) {
      bytes[byteIndex++] =
        (bits[bitIndex] << 7) |
        (bits[bitIndex + 1] << 6) |
        (bits[bitIndex + 2] << 5) |
        (bits[bitIndex + 3] << 4) |
        (bits[bitIndex + 4] << 3) |
        (bits[bitIndex + 5] << 2) |
        (bits[bitIndex + 6] << 1) |
        bits[bitIndex + 7];
      bitIndex += 8;
    }

    // Handle remaining bits if any
    if (bitIndex < length) {
      let lastByte = 0;

      for (let j = 0; j < numLeftoverBits; j++) {
        if (bits[bitIndex + j]) {
          lastByte |= 1 << (7 - j);
        }
      }
      bytes[byteIndex] = lastByte;
    }

    return {type: "bitstring", text: null, bytes, numLeftoverBits};
  }

  static fromText(text) {
    return {type: "bitstring", text, bytes: null, numLeftoverBits: 0};
  }

  static integerSegmentToBytes(segment) {
    const value = segment.value.value;
    const isLittleEndian = $.#isLittleEndian(segment);

    const bitCount = $.#calculateBitCount(segment);
    const completeBytes = Math.floor(bitCount / 8);
    const leftoverBits = bitCount % 8;
    const totalBytes = completeBytes + (leftoverBits > 0 ? 1 : 0);

    const buffer = new ArrayBuffer(totalBytes);
    const result = new Uint8Array(buffer);
    const dataView = new DataView(buffer);

    if (
      value >= BigInt(Number.MIN_SAFE_INTEGER) &&
      value <= BigInt(Number.MAX_SAFE_INTEGER)
    ) {
      const numberValue = Number(value);

      if (bitCount === 8) {
        dataView.setUint8(0, numberValue & 0xff);
        return result;
      } else if (bitCount === 16 && completeBytes === 2) {
        dataView.setUint16(0, numberValue & 0xffff, isLittleEndian);
        return result;
      } else if (bitCount === 32 && completeBytes === 4) {
        dataView.setUint32(0, numberValue & 0xffffffff, isLittleEndian);
        return result;
      }
    }
  }

  static #calculateBitCount(segment) {
    const size = segment.size ? Number(segment.size.value) : 64;
    const unit = segment.unit ? Number(segment.unit.value) : 1;

    return size * unit;
  }

  static #isLittleEndian(segment) {
    return segment.endianness === "little";
  }
}

const $ = Bitstring2;
