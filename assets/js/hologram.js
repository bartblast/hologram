// TODO: test

import { cloneDeep } from 'lodash';

class Hologram {
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
}

class HologramPage {
  static assign(state, key, value) {
    let newState = cloneDeep(state)
    newState.data[HologramPage.objectKey(key)] = value
    return newState;
  }

  static objectKey(key) {
    switch (key.type) {
      case 'atom':
        return `~Hologram.Transpiler.AST.AtomType[${key.value}]`

      case 'string':
        return `~Hologram.Transpiler.AST.StringType[${key.value}]`
        
      default:
        throw 'Not implemented, at HologramPage.objectKey()'
    }
  }
}

window.Hologram = Hologram
window.HologramPage = HologramPage