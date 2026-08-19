"use strict";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";

import {benchmark, benchmarkMemory} from "../../../support/helpers.mjs";
import {defineModel, fillFrame, TASK} from "../../../support/data_layer.mjs";

defineModel();

const frame = fillFrame(10_000);

benchmark(() => {
  LocalDatabase.reset();
  Deltas.apply(frame);
});

// Emptied BEFORE the reading is taken rather than inside it: the timed runs above left a filled
// database behind, and measuring one fill against another of the same size reads as no cost at
// all.
LocalDatabase.reset();

benchmarkMemory(() => {
  Deltas.apply(frame);

  return LocalDatabase.getTable(TASK);
});
