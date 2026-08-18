const helpers = {
  slowValue(ms) {
    return new Promise((resolve) => {
      setTimeout(() => resolve(ms), ms);
    });
  },
};

export default helpers;
