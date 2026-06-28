"use strict";

import Type from "../type.mjs";

export default class ReachEvent {
  // The IntersectionObserver callback has no associated DOM event to cancel, so preventDefault
  // would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(_entry) {
    // A reach event is a pure edge-arrival trigger that carries no data of its own, so its payload
    // is empty. Authors that need to branch on the edge pass it as an action arg instead.
    return Type.map();
  }

  // An IntersectionObserver reports its target both as it comes into view and as it leaves; only the
  // arrival is the reach event, so a non-intersecting entry (the edge scrolling back out) is ignored.
  static isEventIgnored(entry) {
    return !entry.isIntersecting;
  }
}
