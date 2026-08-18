Benchmark

Function: Model.box()\
Argument: 10,000 rows of one entity type - nine attributes wide, two of them datetimes

What it prices: the REJECTED alternative, not a path the client walks. Boxing happens at the
result boundary, for the rows a query returned, memoized per row - never for the whole database.
This is here so the store decision stays checkable against deltas/apply/fill_10k_rows: a boxed
datetime is itself a 13-field boxed map, which is where the memory goes.

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
    <td>136.49 ms</td>
  </tr>
  <tr>
    <th>Average Warm Execution Time</th>
    <td>91.90 ms</td>
  </tr>
  <tr>
    <th>Heap Retained</th>
    <td>79.8 MB</td>
  </tr>
</table>

## Running

From the `assets` directory, with the DOM shim the client modules expect and the collector
exposed for the heap reading:

```
node --expose-gc --require jsdom-global/register ../benchmarks/javascript/model/box/10k_rows/run.mjs
```
