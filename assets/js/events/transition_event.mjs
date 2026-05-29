"use strict";

import Type from "../type.mjs";

export default class TransitionEvent {
  static isDefaultAllowed = false;

  // TODO: add fields specific to TransitionEvent
  static buildOperationParam(_event) {
    return Type.map();
  }

  static isEventIgnored(_event) {
    return false;
  }
}
