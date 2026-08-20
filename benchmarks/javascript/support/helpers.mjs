"use strict";

// What the given function's result costs to HOLD, which is the question a data structure is
// chosen by as much as by what it costs to build.
//
// Run node with --expose-gc: without it the reading includes whatever the collector has not got
// to yet, and the number says more about timing than about the structure. The function must
// RETURN what it keeps - a result nothing references is collected before it can be measured.
export function benchmarkMemory(fun) {
  const collect = () => {
    if (globalThis.gc) {
      globalThis.gc();
    }
  };

  collect();

  const before = process.memoryUsage().heapUsed;
  const retained = fun();

  collect();

  const megabytes = (process.memoryUsage().heapUsed - before) / 1024 / 1024;

  console.log(`Heap retained: ${megabytes.toFixed(1)} MB`);

  return retained;
}

export function benchmark(fun) {
  const WARMUP_ITERATIONS = 100;
  const ITERATIONS = 1_000;

  // Cold measurement (first execution)
  const coldStart = process.hrtime.bigint();
  fun();
  const coldEnd = process.hrtime.bigint();
  const coldTimeMicroseconds = Number(coldEnd - coldStart) / 1_000;

  console.log(`Cold execution: ${coldTimeMicroseconds.toFixed(2)} μs`);

  // Warm up
  for (let i = 0; i < WARMUP_ITERATIONS; i++) {
    fun();
  }

  // Warm measurement
  const warmStart = process.hrtime.bigint();

  for (let i = 0; i < ITERATIONS; i++) {
    fun();
  }

  const warmEnd = process.hrtime.bigint();
  const warmTimeMicroseconds = Number(warmEnd - warmStart) / ITERATIONS / 1_000;

  console.log(`Warm execution: ${warmTimeMicroseconds.toFixed(2)} μs`);
}
