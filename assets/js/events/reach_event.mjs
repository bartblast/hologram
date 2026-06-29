"use strict";

import Type from "../type.mjs";

export default class ReachEvent {
  // A scroll-edge reach has no associated cancelable DOM event, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  static buildOperationParam(_event) {
    // A reach event is a pure edge-arrival trigger that carries no data of its own, so its payload
    // is empty. Authors that need to branch on the edge pass it as an action arg instead.
    return Type.map();
  }

  // The scroll-edge listener gates its own firing, so its {target} events are never ignored. The
  // strict comparison still discards a non-intersecting IntersectionObserver entry - the edge
  // scrolling back out - while the observer-backed path remains.
  static isEventIgnored(event) {
    return event.isIntersecting === false;
  }
}
