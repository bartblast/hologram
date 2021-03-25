// TODO: test

import { cloneDeep } from 'lodash';

function patternMatchFunctionArgs(params, args) {
  if (args.length != params.length) {
    return false;
  }

  for (let i = 0; i < params.length; ++ i) {
    if (!isPatternMatched(params[i], args[i])) {
      return false;
    }
  }

  return true;
}

function isPatternMatched(left, right) {
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

class HolografPage {
  assign(state, key, value) {
    let newState = cloneDeep(state)
    newState.data[objectKey(key)] = value
    return newState;
  }

  objectKey(key) {
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