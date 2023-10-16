"use strict";

import {linkModules, unlinkModules} from "../../assets/js/test_support.mjs";

before(() => linkModules());
after(() => unlinkModules());
