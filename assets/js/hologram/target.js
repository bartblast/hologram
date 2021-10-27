"use strict";

import Runtime from "./runtime";
import Type from "./type";

export default class Target {
  static get TYPE() {
    return {
      layout: "layout",
      page: "page"
    }
  }

  constructor(id) {
    this.id = id
    this.class = Runtime.getComponentClass(id)
    this.module = Type.module(this.class.name)
  }
}