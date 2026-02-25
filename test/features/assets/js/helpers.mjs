const helpers = {
  async asyncSum(a, b) {
    return a + b;
  },

  promiseSum(a, b) {
    return new Promise((resolve) => {
      setTimeout(() => resolve(a + b), 100);
    });
  },  
  
  sum(a, b) {
    return a + b;
  },
}

export default helpers;
