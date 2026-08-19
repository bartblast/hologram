"use strict";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";
import Model from "../../../../../assets/js/model.mjs";

import {benchmark, benchmarkMemory} from "../../../support/helpers.mjs";
import {defineModel, fillFrame, TASK} from "../../../support/data_layer.mjs";

defineModel();

LocalDatabase.reset();
Deltas.apply(fillFrame(10_000));

const rows = Object.values(LocalDatabase.getTable(TASK));

// What a boxed store would have cost, measured against what holding the same rows plain costs
// (the fill benchmark next door). Nothing boxes this many rows in practice - boxing happens at
// the result boundary, for what a query returned - so this is the rejected alternative priced,
// not a path the client walks.
benchmark(() => {
  rows.map((row) => Model.box(TASK, row));
});

benchmarkMemory(() => rows.map((row) => Model.box(TASK, row)));
