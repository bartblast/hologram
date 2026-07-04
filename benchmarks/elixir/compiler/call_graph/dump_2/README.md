Benchmark

Hologram.Compiler.CallGraph.dump/2

## System

Benchmark suite executing on the following system:

<table style="width: 1%">
  <tr>
    <th style="width: 1%; white-space: nowrap">Operating System</th>
    <td>macOS</td>
  </tr><tr>
    <th style="white-space: nowrap">CPU Information</th>
    <td style="white-space: nowrap">Apple M1 Pro</td>
  </tr><tr>
    <th style="white-space: nowrap">Number of Available Cores</th>
    <td style="white-space: nowrap">10</td>
  </tr><tr>
    <th style="white-space: nowrap">Available Memory</th>
    <td style="white-space: nowrap">16 GB</td>
  </tr><tr>
    <th style="white-space: nowrap">Elixir Version</th>
    <td style="white-space: nowrap">1.20.0</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">29.0.1</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">10 s</td>
  </tr><tr>
    <th>:parallel</th>
    <td style="white-space: nowrap">1</td>
  </tr><tr>
    <th>:warmup</th>
    <td style="white-space: nowrap">2 s</td>
  </tr>
</table>

## Statistics



Run Time

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Average</th>
    <th style="text-align: right">Deviation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">21.63</td>
    <td style="white-space: nowrap; text-align: right">46.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.85%</td>
    <td style="white-space: nowrap; text-align: right">44.80 ms</td>
    <td style="white-space: nowrap; text-align: right">87.83 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">21.50</td>
    <td style="white-space: nowrap; text-align: right">46.51 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.52%</td>
    <td style="white-space: nowrap; text-align: right">45.94 ms</td>
    <td style="white-space: nowrap; text-align: right">57.17 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">20.09</td>
    <td style="white-space: nowrap; text-align: right">49.77 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.00%</td>
    <td style="white-space: nowrap; text-align: right">48.44 ms</td>
    <td style="white-space: nowrap; text-align: right">131.96 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap;text-align: right">21.63</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">21.50</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">20.09</td>
    <td style="white-space: nowrap; text-align: right">1.08x</td>
  </tr>

</table>