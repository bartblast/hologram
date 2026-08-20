"use strict";

import Deltas from "../../../../../assets/js/deltas.mjs";
import LocalDatabase from "../../../../../assets/js/local_database.mjs";
import QueryKernel from "../../../../../assets/js/query_kernel.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {
  defineModel,
  fillFrame,
  pageTerms,
} from "../../../support/data_layer.mjs";

defineModel();

// Every from_query prop of a page, re-evaluated - which is what one render costs under the
// naive re-run the reactivity ruling chose.
LocalDatabase.reset();
Deltas.apply(fillFrame(2_000));

const terms = pageTerms();

benchmark(() => {
  terms.forEach((term) => QueryKernel.run(term));
});
