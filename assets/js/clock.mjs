"use strict";

// The stamps this client authors as column revisions: wall_clock_ms * 1024 + logical, the shape
// Hologram.DB.Clock authors on the server. 43 bits of milliseconds and 10 of logical counter keep
// a stamp under JavaScript's 53-bit safe integer, and that split cannot move on one tier alone:
// the server stores a client's stamp exactly as authored and compares it against its own by value.
//
// The receive rule is what makes a stamp usable as an optimistic-concurrency baseline. The clock
// is advanced past every revision that arrives, so a stamp authored here is above everything this
// client has seen. A write's based_on is then simply what the local row holds - equality means the
// client saw the revision the row still carries, and a stamp of its own can never collide with one
// it was told about.
//
// No compare-and-swap, where the server needs one: JavaScript runs the read and the write of #last
// with nothing interleaving.

export default class Clock {
  static #last = 0;

  static #logicalSpan = 1024;

  // Advances the clock past the given stamp, so every stamp authored afterwards is above it.
  static observe(stamp) {
    Clock.#last = Math.max(Clock.#last, stamp);
  }

  // Forgets every stamp authored and observed so far.
  static reset() {
    Clock.#last = 0;
  }

  // Returns the next stamp, above every stamp already authored or observed and at or above the
  // current wall clock.
  static stamp() {
    Clock.#last = Math.max(Clock.#last + 1, Date.now() * Clock.#logicalSpan);

    return Clock.#last;
  }
}
