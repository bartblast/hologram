"use strict";

// What a fake clock replaces and a test must give back. A test that leaves one of these faked
// breaks every file after it: the runtime's timers are armed for real and cleared through a fake
// that does not know them, so a retry or a watchdog nothing can cancel fires in a later test. The
// original is put back here so the rest of the run is sound, and the test is failed by name so
// the leak is fixed where it is made.
const ORIGINALS = {
  Date: globalThis.Date,
  clearInterval: globalThis.clearInterval,
  clearTimeout: globalThis.clearTimeout,
  setInterval: globalThis.setInterval,
  setTimeout: globalThis.setTimeout,
};

export const mochaHooks = {
  afterEach() {
    for (const [name, original] of Object.entries(ORIGINALS)) {
      if (globalThis[name] !== original) {
        globalThis[name] = original;

        throw new Error(
          `${this.currentTest.fullTitle()} left globalThis.${name} replaced`,
        );
      }
    }
  },
};
