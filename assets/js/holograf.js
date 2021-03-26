// TODO: test

import { cloneDeep } from 'lodash';

class Holograf {
  static patternMatchFunctionArgs(params, args) {
    if (args.length != params.length) {
      return false;
    }

    for (let i = 0; i < params.length; ++ i) {
      if (!Holograf.isPatternMatched(params[i], args[i])) {
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

class HolografPage {
  static assign(state, key, value) {
    let newState = cloneDeep(state)
    newState.data[HolografPage.objectKey(key)] = value
    return newState;
  }

  static objectKey(key) {
    switch (key.type) {
      case 'atom':
        return `~Holograf.Transpiler.AST.AtomType[${key.value}]`

      case 'string':
        return `~Holograf.Transpiler.AST.StringType[${key.value}]`
        
      default:
        throw 'Not implemented, at HolografPage.objectKey()'
    }
  }
}

window.Holograf = Holograf
window.HolografPage = HolografPage