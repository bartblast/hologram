"use strict";

import {assert, linkModules, unlinkModules} from "./support/helpers.mjs";

import CommandQueue from "../../assets/js/command_queue.mjs";

describe("CommandQueue", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  it.only("push", () => {
    CommandQueue.items = {};

    CommandQueue.push("dummy_command");

    const id = Object.keys(CommandQueue.items)[0];
    assert.match(
      id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );

    const expectedItems = {};
    expectedItems[id] = {
      id: id,
      command: "dummy_command",
      status: "pending",
    };

    assert.deepStrictEqual(CommandQueue.items, expectedItems);
  });
});
