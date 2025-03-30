"use strict";

import HologramInterpreterError from "./errors/interpreter_error.mjs";

export default class Bitstring2 {
  static concatSegments(segments) {
    if (
      segments.every(
        (segment) => segment.type === "utf8" || segment.type === "binary",
      )
    ) {
      const segmentCount = segments.length;
      let text = "";

      for (let i = 0; i < segmentCount; i++) {
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
    const byteCount = bitCount / 8;
    const buffer = new ArrayBuffer(byteCount);
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
    const bitCount = bits.length;
    const byteCount = Math.ceil(bitCount / 8);
    const numLeftoverBits = bitCount % 8;
    const bytes = new Uint8Array(byteCount);

    // Process 8 bytes at a time when possible
    let byteIndex = 0;
    let bitIndex = 0;

    // Fast path for byte-aligned chunks
    while (bitIndex + 8 <= bitCount) {
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
    if (bitIndex < bitCount) {
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

      // Fast path for standard bit counts
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

      // Hybrid approach: Bitwise operations for small integers, division for larger ones
      const usesBitwiseOps = Math.abs(numberValue) < 0x100000000; // 2^32

      if (isLittleEndian) {
        // Little endian: LSB first
        let remainingValue = numberValue;

        for (let i = 0; i < completeBytes; i++) {
          if (usesBitwiseOps) {
            result[i] = remainingValue & 0xff;
            remainingValue = remainingValue >>> 8;
          } else {
            result[i] = remainingValue % 256;
            remainingValue = Math.floor(remainingValue / 256);
          }
        }

        // Handle leftover bits
        if (leftoverBits > 0) {
          const shiftAmount = 8 - leftoverBits;
          result[completeBytes] =
            (remainingValue & ((1 << leftoverBits) - 1)) << shiftAmount;
        }
      } else {
        // Big endian: MSB first
        if (usesBitwiseOps) {
          // Fast bit shifting approach for small integers
          const totalBitsInInteger = 32;

          // Calculate shift to align with MSB
          const initialShift = totalBitsInInteger - bitCount;
          let shiftedValue =
            initialShift > 0 ? numberValue << initialShift : numberValue;

          // For complete bytes
          for (let i = 0; i < completeBytes; i++) {
            result[i] = (shiftedValue >>> (totalBitsInInteger - 8)) & 0xff;
            shiftedValue = shiftedValue << 8;
          }

          // Handle leftover bits
          if (leftoverBits > 0) {
            result[completeBytes] =
              (shiftedValue >>> (totalBitsInInteger - 8)) & 0xff;
          }
        } else {
          // Division approach for larger integers
          let remainingValue = numberValue;

          // For big-endian, we need to start with the most significant bits
          // Calculate bytes from most significant to least significant
          for (let i = 0; i < completeBytes; i++) {
            // Calculate how many bits we still need to shift
            const bitsToShift = (completeBytes - i - 1) * 8 + leftoverBits;
            // Create a divisor based on that shift
            const divisor = Math.pow(2, bitsToShift);

            // Extract the current byte
            const byteValue = Math.floor(remainingValue / divisor);
            result[i] = byteValue & 0xff;

            // Remove the processed bits
            remainingValue = remainingValue % divisor;
          }

          // Handle leftover bits
          if (leftoverBits > 0) {
            // For leftover bits, we shift them to the most significant bits of the last byte
            result[completeBytes] =
              (remainingValue << (8 - leftoverBits)) & 0xff;
          }
        }
      }
    } else {
      // Special fast path for 64-bit BigInts (common case)
      if (bitCount === 64 && completeBytes === 8 && leftoverBits === 0) {
        const byteMask = 0xffn;

        if (isLittleEndian) {
          // Little endian: LSB first
          for (let i = 0; i < 8; i++) {
            result[i] = Number((value >> BigInt(i * 8)) & byteMask);
          }
        } else {
          // Big endian: MSB first
          for (let i = 0; i < 8; i++) {
            result[i] = Number((value >> BigInt(56 - i * 8)) & byteMask);
          }
        }
        return result;
      }

      // Fast path for byte-aligned BigInts (no leftover bits)
      if (leftoverBits === 0) {
        const byteMask = 0xffn;

        if (isLittleEndian) {
          // Little endian: LSB first
          let remainingValue = value;
          for (let i = 0; i < completeBytes; i++) {
            result[i] = Number(remainingValue & byteMask);
            remainingValue = remainingValue >> 8n;
          }
        } else {
          // Big endian: MSB first
          const totalBits = BigInt(completeBytes * 8);

          for (let i = 0; i < completeBytes; i++) {
            const shift = totalBits - BigInt((i + 1) * 8);
            result[i] = Number((value >> shift) & byteMask);
          }
        }
        return result;
      }

      // Handle cases with leftover bits (not byte-aligned)
      const byteMask = 0xffn;

      if (isLittleEndian) {
        // Little endian: LSB first
        let remainingValue = value;

        // Process complete bytes
        for (let i = 0; i < completeBytes; i++) {
          result[i] = Number(remainingValue & byteMask);
          remainingValue = remainingValue >> 8n;
        }

        // Handle leftover bits - shift to the most significant bits of the byte
        if (leftoverBits > 0) {
          const leftoverMask = (1n << BigInt(leftoverBits)) - 1n;
          const shiftAmount = BigInt(8 - leftoverBits);
          result[completeBytes] = Number(
            (remainingValue & leftoverMask) << shiftAmount,
          );
        }
      } else {
        // Big endian: MSB first

        // Calculate total bits needed
        const totalBits = BigInt(completeBytes * 8 + leftoverBits);
        let remainingValue = value;

        // Process complete bytes
        for (let i = 0; i < completeBytes; i++) {
          // Calculate how many bits we still need to shift right to get the current byte
          const shift = totalBits - BigInt((i + 1) * 8);
          result[i] = Number((remainingValue >> shift) & byteMask);
        }

        // Handle leftover bits
        if (leftoverBits > 0) {
          // For leftover bits, we need to:
          // 1. Get the remaining value (last bits)
          // 2. Shift it left to align with MSB of the last byte
          const remainingBits =
            remainingValue & ((1n << BigInt(leftoverBits)) - 1n);
          result[completeBytes] = Number(
            remainingBits << BigInt(8 - leftoverBits),
          );
        }
      }
    }

    return result;
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
