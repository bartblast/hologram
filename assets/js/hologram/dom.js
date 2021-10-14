"use strict";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([attributesModule, eventListenersModule]);

export default class DOM {
  static PRUNED_ATTRS = ["on_click"]

  // TODO: finish & test
  static buildVNode(node) {
    switch (node.type) {
      case "text":
        return DOM.buildTextVNode(node)
    }
  }

  static buildTextVNode(node) {
    return [node.content]
  }
}