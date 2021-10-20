"use strict";

import Runtime from "./runtime";
import Type from "./type";

export default class Target {
  constructor(id) {
    this.id = id
    this.class = Runtime.getComponentClass(id)
    this.module = Type.module(this.class.name)
  }
}