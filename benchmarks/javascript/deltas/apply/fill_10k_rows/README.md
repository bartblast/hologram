Benchmark

Function: Deltas.apply()\
Argument: a frame putting 10,000 rows of one entity type - nine attributes wide, two of them
datetimes, one of them ordered by (so a sort key is derived per row)

What it prices: the whole-app fill every client pays on connect, and what the filled database
costs to hold. The heap figure is the one the plain-row store was chosen on - the same rows as
boxed entity structs are measured next door, under model/box/10k_rows.

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
    <td>43.09 ms</td>
  </tr>
  <tr>
    <th>Average Warm Execution Time</th>
    <td>26.38 ms</td>
  </tr>
  <tr>
    <th>Heap Retained</th>
    <td>7.1 MB</td>
  </tr>
</table>

## Running

From the `assets` directory, with the DOM shim the client modules expect and the collector
exposed for the heap reading:

```sh
node --expose-gc --require jsdom-global/register ../benchmarks/javascript/deltas/apply/fill_10k_rows/run.mjs
```
