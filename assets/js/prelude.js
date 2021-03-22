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
  let lType = left.__type__;
  let rType = right.__type__;

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