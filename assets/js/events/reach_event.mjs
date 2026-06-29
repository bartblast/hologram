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

  // The scroll-edge listener gates its own firing, so its events are never ignored here.
  static isEventIgnored(_event) {
    return false;
  }
}
