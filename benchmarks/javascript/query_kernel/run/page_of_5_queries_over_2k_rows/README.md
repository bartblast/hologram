Benchmark

Function: QueryKernel.run()\
Argument: five terms over a 2,000-row table - a plain filter, a filter ordered by a string with a
limit, a comparison with a limit, a count, and a single-result lookup by id

What it prices: one render's worth of query evaluation under the naive re-run the reactivity
ruling chose - every from_query prop of a page re-evaluated, against a 16.7 ms frame.

## System

<table>
  <tr>
    <th>Operating System</th>
    <td>macOS 26.5</td>
  </tr>
  <tr>
    <th>CPU</th>
    <td>Apple M1 Pro</td>
  </tr>
  <tr>
    <th>Number of CPU Cores</th>
    <td>10</td>
  </tr>
  <tr>
    <th>RAM</th>
    <td>16 GB</td>
  </tr>
  <tr>
    <th>Elixir Version</th>
    <td>1.20.0</td>
  </tr>
  <tr>
    <th>Erlang/OTP Version</th>
    <td>29</td>
  </tr>
  <tr>
    <th>Node.js Version</th>
    <td>24.13.0</td>
  </tr>
</table>

## Statistics

<table>
  <tr>
    <th>Average Cold Execution Time</th>
    <td>5.77 ms</td>
  </tr>
  <tr>
    <th>Average Warm Execution Time</th>
    <td>2.20 ms</td>
  </tr>
</table>

## Running

From the `assets` directory, with the DOM shim the client modules expect and the collector
exposed for the heap reading:

```
node --expose-gc --require jsdom-global/register ../benchmarks/javascript/query_kernel/run/page_of_5_queries_over_2k_rows/run.mjs
```
