"use strict";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {
  defineModel,
  fillFrame,
  patchFrame,
} from "../../../support/data_layer.mjs";

defineModel();

// A frame of changes arriving on a filled database, which is what a client applies while
// someone is looking at the page.
LocalDatabase.reset();
Deltas.apply(fillFrame(10_000));

const patches = patchFrame(50);

benchmark(() => {
  Deltas.apply(patches);
});
