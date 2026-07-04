Benchmark

Hologram.Compiler.CallGraph.remove_vertices/2

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
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.60 M</td>
    <td style="white-space: nowrap; text-align: right">626.35 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;70.15%</td>
    <td style="white-space: nowrap; text-align: right">584 ns</td>
    <td style="white-space: nowrap; text-align: right">2492.86 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.15 M</td>
    <td style="white-space: nowrap; text-align: right">867.02 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.40%</td>
    <td style="white-space: nowrap; text-align: right">792 ns</td>
    <td style="white-space: nowrap; text-align: right">2063.68 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.02 M</td>
    <td style="white-space: nowrap; text-align: right">981.95 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.87%</td>
    <td style="white-space: nowrap; text-align: right">958 ns</td>
    <td style="white-space: nowrap; text-align: right">2266.12 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.79 M</td>
    <td style="white-space: nowrap; text-align: right">1261.71 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.81%</td>
    <td style="white-space: nowrap; text-align: right">1250 ns</td>
    <td style="white-space: nowrap; text-align: right">2858.90 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.48 M</td>
    <td style="white-space: nowrap; text-align: right">2104.55 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;85.52%</td>
    <td style="white-space: nowrap; text-align: right">2041 ns</td>
    <td style="white-space: nowrap; text-align: right">4288.16 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">0.00005 M</td>
    <td style="white-space: nowrap; text-align: right">20805842.02 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.44%</td>
    <td style="white-space: nowrap; text-align: right">20644685.40 ns</td>
    <td style="white-space: nowrap; text-align: right">21533733.30 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap;text-align: right">1.60 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.15 M</td>
    <td style="white-space: nowrap; text-align: right">1.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.02 M</td>
    <td style="white-space: nowrap; text-align: right">1.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.79 M</td>
    <td style="white-space: nowrap; text-align: right">2.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.48 M</td>
    <td style="white-space: nowrap; text-align: right">3.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">0.00005 M</td>
    <td style="white-space: nowrap; text-align: right">33217.59x</td>
  </tr>

</table>