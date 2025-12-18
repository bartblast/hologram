"use strict";

import NodeTable from "./erts/node_table.mjs";
import Sequence from "./common/sequence.mjs";

export default class ERTS {
  static nodeTable = NodeTable;
  static referenceSequence = new Sequence();
}
