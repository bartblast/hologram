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
    <td style="white-space: nowrap">1.18.2</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">27.2.4</td>
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
    <th style="text-align: right">Devitation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">25.95</td>
    <td style="white-space: nowrap; text-align: right">38.54 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.76%</td>
    <td style="white-space: nowrap; text-align: right">38.12 ms</td>
    <td style="white-space: nowrap; text-align: right">45.44 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">25.91</td>
    <td style="white-space: nowrap; text-align: right">38.59 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.75%</td>
    <td style="white-space: nowrap; text-align: right">38.17 ms</td>
    <td style="white-space: nowrap; text-align: right">53.09 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">25.90</td>
    <td style="white-space: nowrap; text-align: right">38.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.06%</td>
    <td style="white-space: nowrap; text-align: right">38.18 ms</td>
    <td style="white-space: nowrap; text-align: right">47.71 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap;text-align: right">25.95</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">25.91</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">25.90</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
  </tr>

</table>