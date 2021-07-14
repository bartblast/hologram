import "core-js/stable";
import "regenerator-runtime/runtime"; 

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([eventListenersModule, attributesModule]);

import Client from "./hologram/client"
import DOM from "./hologram/dom"

export default class Hologram {
  static onReady(document, callback) {
    if (
      document.readyState === "interactive" ||
      document.readyState === "complete"
    ) {
      callback();
    } else {
      document.addEventListener("DOMContentLoaded", function listener() {
        document.removeEventListener("DOMContentLoaded", listener);
        callback();
      });
    }
  }

  static async start(window, pageModule) {
    Hologram.onReady(window.document, () => {
      this.client = new Client()

      let container = window.document.body
      window.prev_vnode = toVNode(container)
      let context = {scopeModule: pageModule, pageModule: pageModule}
      window.prev_vnode = Hologram.render(window.prev_vnode, context)
    })
  }

  // TODO: refactor & test functions below

  static build_vnode(node, state, context) {
    if (Array.isArray(node)) {
      return node.reduce((acc, n) => {
        acc.push(...Hologram.build_vnode(n, state, context))
        return acc
      }, [])
    }

    switch (node.type) {
      case "component":
        let module = Hologram.get_module(node.module)

        if (module.hasOwnProperty("action")) {
          context = Object.assign({}, context)
          context.scopeModule = module
        }

        return Hologram.build_vnode(node.children, state, context)

      case "element":
        let children = node.children.reduce((acc, child) => {
          acc.push(...Hologram.build_vnode(child, state, context))
          return acc
        }, [])

        let event_handlers = DOM.buildVNodeEventHandlers(node, state, context)
        let attrs = DOM.buildVNodeAttrs(node)

        return [h(node.tag, {attrs: attrs, on: event_handlers}, children)]

      case "expression":
        return [Hologram.evaluate(node.callback(state))]

      case "text":
        return [node.content]
    } 
  }

  static evaluate(value) {
    switch (value.type) {
      case "integer":
        return `${value.value}`
    }
  }

  static get_module(name) {
    return eval(name.replace(/\./g, ""))
  }

  static isPatternMatched(left, right) {
    let lType = left.type;
    let rType = right.type;

    if (lType != 'placeholder') {
      if (lType != rType) {
        return false;
      }

      if (lType == 'atom' && left.value != right.value) {
        return false;
      }
    }

    return true;
  }

  static js(js) {
    eval(js.value)
  }

  static objectKey(key) {
    switch (key.type) {
      case 'atom':
        return `~atom[${key.value}]`

      case 'string':
        return `~string[${key.value}]`
        
      default:
        throw 'Not implemented, at HologramPage.objectKey()'
    }
  }

  static patternMatchFunctionArgs(params, args) {
    if (args.length != params.length) {
      return false;
    }

    for (let i = 0; i < params.length; ++ i) {
      if (!Hologram.isPatternMatched(params[i], args[i])) {
        return false;
      }
    }

    return true;
  }

  static render(prev_vnode, context) {
    let template = context.pageModule.template()
    context.scopeModule = context.pageModule
    let vnode = Hologram.build_vnode(template, window.state, context)[0]
    patch(prev_vnode, vnode)

    return vnode
  }
}

class Kernel {
  static $add(left, right) {
    let type = left.type == "integer" && right.type == "integer" ? "integer" : "float"
    return { type: type, value: left.value + right.value }
  }

  static $dot(left, right) {
    return cloneDeep(left.data[Hologram.objectKey(right)])
  }
}

class Map {
  static put(map, key, value) {
    let mapClone = cloneDeep(map)
    mapClone.data[Hologram.objectKey(key)] = value
    return mapClone;
  }
}

window.Hologram = Hologram
window.Kernel = Kernel
window.Map = Map