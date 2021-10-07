"use strict";

import { assert, mockWindow } from "./support/commons";
import Store from "../../assets/js/hologram/store";

describe("getInstance()", () => {
  it("creates a new Store object if it doesn't exist yet", () => {
    const window = mockWindow()
    const store = Store.getInstance(window)

    assert.isTrue(store instanceof Store)
    assert.equal(window.__hologramStore__, store)
  })

  it("doesn't create a new Store object if it already exists", () => {
    const window = mockWindow()
    const store1 = Store.getInstance(window)
    const store2 = Store.getInstance(window)

    assert.equal(store2, store1)
  })
})