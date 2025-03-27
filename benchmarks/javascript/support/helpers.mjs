"use strict";

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
