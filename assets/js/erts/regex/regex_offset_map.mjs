"use strict";

// How many UTF-16 units apart, at least, the checkpoints of a map are.
const CHECKPOINT_GAP = 64;

// Converts between the JS string indices of a text and the UTF-8 byte offsets
// of the same positions. Walks the text forward from the nearest checkpoint,
// or from where the previous conversion started or stopped when that is
// nearer. A conversion walks at most one checkpoint gap, conversions in
// increasing order walk the text once in total, and a conversion at or after
// the previous one's start walks only from there.
// Checkpoints are laid down as the walks reach them. ASCII text with a known
// byte length maps positions as they are.
export default class RegexOffsetMap {
  // Byte offset and JS string index of checkpoint k, the first code point
  // boundary at or after index k * CHECKPOINT_GAP
  #checkpointByteOffsets = [0];
  #checkpointIndices = [0];

  // Where the previous conversion stopped
  #cursorByteOffset = 0;
  #cursorIndex = 0;

  // Where the previous conversion started its walk
  #walkStartByteOffset = 0;
  #walkStartIndex = 0;

  #byteLength;
  #isAscii;
  #text;

  // The byte length is null when unknown.
  constructor(text, byteLength) {
    this.#byteLength = byteLength;
    this.#isAscii = byteLength === text.length;
    this.#text = text;
  }

  // Returns the UTF-8 byte length of the text.
  byteLength() {
    if (this.#byteLength === null) {
      this.#byteLength = this.toByteOffset(this.#text.length);
    }

    return this.#byteLength;
  }

  // Converts a JS string index, up to the text length, to a byte offset. An
  // index inside a surrogate pair maps to the offset after the pair.
  toByteOffset(index) {
    if (this.#isAscii) return index;

    const checkpoint = Math.min(
      Math.floor(index / CHECKPOINT_GAP),
      this.#checkpointIndices.length - 1,
    );

    let startIndex = this.#checkpointIndices[checkpoint];
    let startByteOffset = this.#checkpointByteOffsets[checkpoint];

    // Checkpoint k can sit one unit past k * CHECKPOINT_GAP, after the index
    if (startIndex > index) {
      startIndex = this.#checkpointIndices[checkpoint - 1];
      startByteOffset = this.#checkpointByteOffsets[checkpoint - 1];
    }

    if (this.#cursorIndex <= index && this.#cursorIndex > startIndex) {
      startIndex = this.#cursorIndex;
      startByteOffset = this.#cursorByteOffset;
    }

    if (this.#walkStartIndex <= index && this.#walkStartIndex > startIndex) {
      startIndex = this.#walkStartIndex;
      startByteOffset = this.#walkStartByteOffset;
    }

    this.#walk(startIndex, startByteOffset, index, Infinity);

    return this.#cursorByteOffset;
  }

  // Converts a byte offset to a JS string index. An offset inside a character
  // maps to the index after it, and an offset past the end to the text
  // length.
  toIndex(byteOffset) {
    if (this.#isAscii) return Math.min(byteOffset, this.#text.length);

    const checkpoint = this.#lastCheckpointAtOrBefore(byteOffset);
    let startIndex = this.#checkpointIndices[checkpoint];
    let startByteOffset = this.#checkpointByteOffsets[checkpoint];

    if (
      this.#cursorByteOffset <= byteOffset &&
      this.#cursorByteOffset > startByteOffset
    ) {
      startIndex = this.#cursorIndex;
      startByteOffset = this.#cursorByteOffset;
    }

    if (
      this.#walkStartByteOffset <= byteOffset &&
      this.#walkStartByteOffset > startByteOffset
    ) {
      startIndex = this.#walkStartIndex;
      startByteOffset = this.#walkStartByteOffset;
    }

    this.#walk(startIndex, startByteOffset, Infinity, byteOffset);

    return this.#cursorIndex;
  }

  // Binary search over the checkpoints laid down so far
  #lastCheckpointAtOrBefore(byteOffset) {
    let low = 0;
    let high = this.#checkpointByteOffsets.length - 1;

    while (low < high) {
      const middle = (low + high + 1) >> 1;

      if (this.#checkpointByteOffsets[middle] <= byteOffset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }

    return low;
  }

  // Walks code points forward from the start position while it's before both
  // limits and the end of the text, laying down the checkpoints it reaches.
  // Records where it starts and leaves the cursor where it stops.
  #walk(index, byteOffset, untilIndex, untilByteOffset) {
    this.#walkStartByteOffset = byteOffset;
    this.#walkStartIndex = index;

    const text = this.#text;
    const length = text.length;

    while (
      index < untilIndex &&
      byteOffset < untilByteOffset &&
      index < length
    ) {
      const codePoint = text.codePointAt(index);

      if (codePoint <= 0x7f) {
        byteOffset += 1;
        index += 1;
      } else if (codePoint <= 0x7ff) {
        byteOffset += 2;
        index += 1;
      } else if (codePoint <= 0xffff) {
        byteOffset += 3;
        index += 1;
      } else {
        byteOffset += 4;
        index += 2;
      }

      if (index >= this.#checkpointIndices.length * CHECKPOINT_GAP) {
        this.#checkpointByteOffsets.push(byteOffset);
        this.#checkpointIndices.push(index);
      }
    }

    this.#cursorByteOffset = byteOffset;
    this.#cursorIndex = index;
  }
}
