// TODO: test

// see: https://www.blazemeter.com/blog/the-correct-way-to-import-lodash-libraries-a-benchmark
import cloneDeep from 'lodash/cloneDeep';
import { DiffDOM } from "diff-dom"

class Hologram {
  static evaluate(value) {
    switch (value.type) {
      case "integer":
        return `${value.value}`
    }
  }

  static isPatternMatched(left, right) {
    let lType = left.type;
    let rType = right.type;

    if (lType != 'variable') {
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
        return `~Hologram.Compiler.AST.AtomType[${key.value}]`

      case 'string':
        return `~Hologram.Compiler.AST.StringType[${key.value}]`
        
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

  static render(ir, state) {
    if (Array.isArray(ir)) {
      return ir.map((node) => { return Hologram.render(node, state)}).join("")
    }

    switch (ir.type) {
      case "expression":
        return Hologram.evaluate(ir.callback(state))
        
      case "tag_node":
        let attrs = Object.keys(ir.attrs).reduce((acc, key) => {
          return acc.concat([`${key}="${ir.attrs[key]}"`])
        }, []).join(" ")

        let children = ir.children.map((child) => {
          return Hologram.render(child, state)
        }).join("")

        return `<${ir.tag} ${attrs}>${children}</${ir.tag}>`

      case "text_node":
        return ir.text
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

  static startEventLoop(window, module, moduleName) {
    let dd = new DiffDOM();

    let callback = () => {
      document.querySelectorAll("[holo-click]").forEach(element => {
        element.addEventListener("click", () => {
          let fun = module["action"]
          let action = { type: 'atom', value: element.getAttribute("holo-click") }

          console.log(`Function call: ${moduleName}.action()`)
          console.debug([action, {}, window.state])
          
          window.state = fun(action, {}, window.state)

          console.log("State after action:")
          console.debug(window.state.data)

          let html = Hologram.render(window.ir[moduleName], window.state)
          let diff = dd.diff(window.document.body, "<body>" + html + "</body>");
          dd.apply(window.document.body, diff)
        })
      })
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