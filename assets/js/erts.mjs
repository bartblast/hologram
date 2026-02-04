"use strict";

import BinaryPatternRegistry from "./erts/binary_pattern_registry.mjs";
import NodeTable from "./erts/node_table.mjs";
import Sequence from "./common/sequence.mjs";
import Type from "./type.mjs";

export default class ERTS {
  // The PID of the init process (#PID<0.0.0>), which is the first process started
  // by the Erlang runtime.
  // Lazy getter to avoid circular dependency with Type.
  static #initPid = null;
  static get INIT_PID() {
    if (!$.#initPid) {
      $.#initPid = Type.pid(NodeTable.CLIENT_NODE, [0, 0, 0], "client");
    }
    return $.#initPid;
  }

  static binaryPatternRegistry = BinaryPatternRegistry;
  static ets = {};

  // Sequence for anonymous function `uniq` field.
  // Used to derive fun_info/1 fields: index, new_index, uniq, new_uniq.
  // In Erlang, index/new_index are per-module indices, and uniq/new_uniq are
  // calculated from compiled code; here we use a global sequence for all.
  static funSequence = new Sequence();

  static graphemeSegmenter = new Intl.Segmenter(undefined, {
    granularity: "grapheme",
  });

  static nodeTable = NodeTable;
  static referenceSequence = new Sequence();
  static uniqueIntegerSequence = new Sequence();
  static utf8Decoder = new TextDecoder("utf-8", {fatal: true});
}

const $ = ERTS;
