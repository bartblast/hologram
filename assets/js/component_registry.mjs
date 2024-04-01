"use strict";

import Type from "./type.mjs";

export default class ComponentRegistry {
  static data = Type.map([]);

  static hydrate(data) {
    ComponentRegistry.data = data;
  }
}
