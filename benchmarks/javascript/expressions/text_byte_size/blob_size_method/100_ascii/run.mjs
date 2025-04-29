"use strict";

import {benchmark} from "../../../../support/helpers.mjs";

const text =
  "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij";

benchmark(() => {
  new Blob([text]).size;
});
