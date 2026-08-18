"use strict";

// The support modules come first on purpose: assets/js/type.mjs and assets/js/erts.mjs import
// one another, and erts reads Type at module scope - so whichever import order a script
// establishes first decides whether that read lands before Type exists. The test helpers these
// pull in establish the order the suite already runs under.

import {benchmark, benchmarkMemory} from "../../../support/helpers.mjs";
import {defineModel, fillFrame, TASK} from "../../../support/data_layer.mjs";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";

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
