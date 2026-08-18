"use strict";

// The support modules come first on purpose: assets/js/type.mjs and assets/js/erts.mjs import
// one another, and erts reads Type at module scope - so whichever import order a script
// establishes first decides whether that read lands before Type exists. The test helpers these
// pull in establish the order the suite already runs under.

import {benchmark} from "../../../support/helpers.mjs";
import {
  defineModel,
  fillFrame,
  patchFrame,
} from "../../../support/data_layer.mjs";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";

defineModel();

// A frame of changes arriving on a filled database, which is what a client applies while
// someone is looking at the page.
LocalDatabase.reset();
Deltas.apply(fillFrame(10_000));

const patches = patchFrame(50);

benchmark(() => {
  Deltas.apply(patches);
});
