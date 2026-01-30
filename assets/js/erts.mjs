"use strict";

import BinaryPatternRegistry from "./erts/binary_pattern_registry.mjs";
import NodeTable from "./erts/node_table.mjs";
import Sequence from "./common/sequence.mjs";

export default class ERTS {
  static binaryPatternRegistry = BinaryPatternRegistry;
  static ets = {};

  static graphemeSegmenter = new Intl.Segmenter(undefined, {
    granularity: "grapheme",
  });

  static nodeTable = NodeTable;
  static referenceSequence = new Sequence();
  static uniqueIntegerSequence = new Sequence();
  static utf8Decoder = new TextDecoder("utf-8", {fatal: true});
}
