Benchmark

Function: Deltas.apply()\
Argument: a frame of 50 patch_entity deltas, applied to a database already holding 10,000 rows

What it prices: a steady-state frame arriving while someone is looking at the page - each patch
merges into its held row and re-derives that row's sort key.

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
    <td>0.33 ms</td>
  </tr>
  <tr>
    <th>Average Warm Execution Time</th>
    <td>0.10 ms</td>
  </tr>
</table>

## Running

From the `assets` directory, with the DOM shim the client modules expect and the collector
exposed for the heap reading:

```sh
node --expose-gc --require jsdom-global/register ../benchmarks/javascript/deltas/apply/patch_frame_50_deltas/run.mjs
```
