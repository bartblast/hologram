// TODO: test

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from "lodash/cloneDeep";

import {attributesModule, eventListenersModule, h, init, toVNode} from "snabbdom";
const patch = init([eventListenersModule, attributesModule]);

class Hologram {
  static build_vnode(node, state, context) {
    if (Array.isArray(node)) {
      return node.map((n) => { return Hologram.build_vnode(n, state, context)})
    }

    switch (node.type) {
      case "component":
        // TODO: implement
        return [h("section", {}, [])]

      case "element":
        let children = node.children.reduce((acc, child) => {
          acc.push(...Hologram.build_vnode(child, state, context))
          return acc
        }, [])

        let event_handlers = Hologram.build_vnode_event_handlers(node, state, context)
        let attrs = Hologram.build_vnode_attrs(node)

        return [h(node.tag, {attrs: attrs, on: event_handlers}, children)]

      case "expression":
        return [Hologram.evaluate(node.callback(state))]

      case "text":
        return [node.content]
    } 
  }

  static build_vnode_attrs(node) {
    delete node.attrs.on_click
    return node.attrs
  }

  static build_vnode_event_handlers(node, state, context) {
    let event_handlers = {}

    if (node.attrs.on_click) {
      event_handlers.click = Hologram.click_handler.bind(null, context.module, node.attrs.on_click, state)
    }

    return event_handlers
  }

  static click_handler(module, action, state, _event) {
    module.action({ type: 'atom', value: action }, {}, state)
  }

  static evaluate(value) {
    switch (value.type) {
      case "integer":
        return `${value.value}`
    }
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

  static onReady(document, callback) {
    if (
      document.readyState === "interactive" ||
      document.readyState === "complete"
    ) {
      callback();
    } else {
      let that = this;
      document.addEventListener("DOMContentLoaded", function listener() {
        document.removeEventListener("DOMContentLoaded", listener);
        callback();
      });
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

  static start_runtime(window, module, moduleName) {
    // TODO: implement click handler
    // let callback = () => {
    //   document.querySelectorAll("[holo-click]").forEach(element => {
    //     element.addEventListener("click", () => {
    //       let fun = module["action"]
    //       let action = { type: 'atom', value: element.getAttribute("holo-click") }

    //       console.log(`Function call: ${moduleName}.action()`)
    //       console.debug([action, {}, window.state])
          
    //       window.state = fun(action, {}, window.state)

    //       console.log("State after action:")
    //       console.debug(window.state.data)

    //       let html = Hologram.template(window.ir[moduleName], window.state)
    //       let diff = dd.diff(window.document.body, "<body>" + html + "</body>");
    //       dd.apply(window.document.body, diff)
    //     })
    //   })
    // }   

    const callback = () => {
      let container = window.document.body
      let context = {module: module}
      let vnode = Hologram.build_vnode(module.template(), window.state, context)[0][0]
      patch(toVNode(container), vnode)
    }

    Hologram.onReady(window.document, callback)
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