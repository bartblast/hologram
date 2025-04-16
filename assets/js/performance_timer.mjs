"use strict";

export default class PerformanceTimer {
  static diff(startTime) {
    const diff = performance.now() - startTime;

    if (diff < 1) {
      return `${Math.round(diff * 1000)} μs`;
    }

    return `${Math.round(diff)} ms`;
  }

  static start() {
    return performance.now();
  }
}
