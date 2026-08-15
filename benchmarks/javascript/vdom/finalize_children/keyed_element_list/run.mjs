"use strict";

import Vdom from "../../../../../assets/js/vdom.mjs";

import {benchmark} from "../../../support/helpers.mjs";
import {defineRuntimeGlobals} from "../../../../../test/javascript/support/helpers.mjs";

import {h} from "../../../../../assets/js/vendor/snabbdom/build/index.js";

defineRuntimeGlobals();

const ITEM_COUNT = 100;

// The keys repeat the way a loop's do, so every item past the first of each key is renumbered.
const children = Array.from({length: ITEM_COUNT}, (_value, index) =>
  h("li", {attrs: {class: "my_class"}, key: `1a2b3c:${index % 3}`}, []),
);

const originalKeys = children.map((child) => child.key);

// Numbering rewrites the keys in place, and a list already numbered has no repeats left to find.
// Restoring them is what keeps every iteration measuring the same work - it is a pair of
// assignments per child, so it is counted in the result but does not dominate it.
const restoreKeys = () => {
  for (let index = 0; index < children.length; index += 1) {
    children[index].key = originalKeys[index];
    children[index].data.key = originalKeys[index];
  }
};

benchmark(() => {
  restoreKeys();
  Vdom.finalizeChildren(children);
});
