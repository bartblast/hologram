"use strict";

import {linkModules, unlinkModules} from "./support/helpers.mjs";

before(() => linkModules());
after(() => unlinkModules());
