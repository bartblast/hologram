const helpers = {
  async asyncSum(a, b) {
    return a + b;
  },

  mapArray(arr, fn) {
    return arr.map(fn);
  },

  promiseSum(a, b) {
    return new Promise((resolve) => {
      setTimeout(() => resolve(a + b), 100);
    });
  },

  sum(a, b) {
    return a + b;
  },
};

export class AsyncCounter {
  constructor(initial) {
    return new Promise((resolve) => {
      setTimeout(() => resolve({value: initial + 1}), 50);
    });
  }
}

export function multiply(a, b) {
  return a * b;
}

export const promiseValue = {
  data: new Promise((resolve) => {
    setTimeout(() => resolve(77), 50);
  }),
};

export default helpers;
