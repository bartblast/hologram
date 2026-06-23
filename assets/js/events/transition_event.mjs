"use strict";

import Type from "../type.mjs";

export default class TransitionEvent {
  // The DOM transition events are not cancelable, so preventDefault would be a no-op.
  static isDefaultAllowed = true;

  // TODO: add fields specific to TransitionEvent
  static buildOperationParam(_event) {
    return Type.map();
  }

  static isEventIgnored(_event) {
    return false;
  }
}
