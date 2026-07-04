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
    <td style="white-space: nowrap; text-align: right">1.72 M</td>
    <td style="white-space: nowrap; text-align: right">580.59 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;67.28%</td>
    <td style="white-space: nowrap; text-align: right">542 ns</td>
    <td style="white-space: nowrap; text-align: right">2024.90 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">1.61 M</td>
    <td style="white-space: nowrap; text-align: right">622.85 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;57.85%</td>
    <td style="white-space: nowrap; text-align: right">583 ns</td>
    <td style="white-space: nowrap; text-align: right">2221.45 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.33 M</td>
    <td style="white-space: nowrap; text-align: right">752.06 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;48.02%</td>
    <td style="white-space: nowrap; text-align: right">708 ns</td>
    <td style="white-space: nowrap; text-align: right">1917 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.05 M</td>
    <td style="white-space: nowrap; text-align: right">953.11 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.89%</td>
    <td style="white-space: nowrap; text-align: right">916 ns</td>
    <td style="white-space: nowrap; text-align: right">1985.96 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.82 M</td>
    <td style="white-space: nowrap; text-align: right">1223.00 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.19%</td>
    <td style="white-space: nowrap; text-align: right">1167 ns</td>
    <td style="white-space: nowrap; text-align: right">2314.41 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.54 M</td>
    <td style="white-space: nowrap; text-align: right">1861.07 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.38%</td>
    <td style="white-space: nowrap; text-align: right">1833 ns</td>
    <td style="white-space: nowrap; text-align: right">3431.16 ns</td>
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
    <td style="white-space: nowrap;text-align: right">1.72 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">1.61 M</td>
    <td style="white-space: nowrap; text-align: right">1.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.33 M</td>
    <td style="white-space: nowrap; text-align: right">1.3x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">1.05 M</td>
    <td style="white-space: nowrap; text-align: right">1.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.82 M</td>
    <td style="white-space: nowrap; text-align: right">2.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.54 M</td>
    <td style="white-space: nowrap; text-align: right">3.21x</td>
  </tr>

</table>