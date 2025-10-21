Benchmark

Hologram.Compiler.CallGraph.patch/3

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
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">209058.51</td>
    <td style="white-space: nowrap; text-align: right">0.00478 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.95%</td>
    <td style="white-space: nowrap; text-align: right">0.00467 ms</td>
    <td style="white-space: nowrap; text-align: right">0.00717 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">1815.47</td>
    <td style="white-space: nowrap; text-align: right">0.55 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.17%</td>
    <td style="white-space: nowrap; text-align: right">0.55 ms</td>
    <td style="white-space: nowrap; text-align: right">0.58 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">717.97</td>
    <td style="white-space: nowrap; text-align: right">1.39 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.25%</td>
    <td style="white-space: nowrap; text-align: right">1.37 ms</td>
    <td style="white-space: nowrap; text-align: right">1.49 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">305.48</td>
    <td style="white-space: nowrap; text-align: right">3.27 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.46%</td>
    <td style="white-space: nowrap; text-align: right">3.22 ms</td>
    <td style="white-space: nowrap; text-align: right">3.78 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">243.52</td>
    <td style="white-space: nowrap; text-align: right">4.11 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.00%</td>
    <td style="white-space: nowrap; text-align: right">4.12 ms</td>
    <td style="white-space: nowrap; text-align: right">4.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">97.99</td>
    <td style="white-space: nowrap; text-align: right">10.20 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.01%</td>
    <td style="white-space: nowrap; text-align: right">10.18 ms</td>
    <td style="white-space: nowrap; text-align: right">11.19 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">32.58</td>
    <td style="white-space: nowrap; text-align: right">30.69 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.39%</td>
    <td style="white-space: nowrap; text-align: right">30.50 ms</td>
    <td style="white-space: nowrap; text-align: right">32.07 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">25.86</td>
    <td style="white-space: nowrap; text-align: right">38.67 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.43%</td>
    <td style="white-space: nowrap; text-align: right">38.66 ms</td>
    <td style="white-space: nowrap; text-align: right">39.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">2.02</td>
    <td style="white-space: nowrap; text-align: right">494.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.69%</td>
    <td style="white-space: nowrap; text-align: right">492.47 ms</td>
    <td style="white-space: nowrap; text-align: right">516.85 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.89</td>
    <td style="white-space: nowrap; text-align: right">1117.56 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.44%</td>
    <td style="white-space: nowrap; text-align: right">1120.99 ms</td>
    <td style="white-space: nowrap; text-align: right">1137.41 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">1311.28 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.97%</td>
    <td style="white-space: nowrap; text-align: right">1310.57 ms</td>
    <td style="white-space: nowrap; text-align: right">1331.58 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.32</td>
    <td style="white-space: nowrap; text-align: right">3170.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.72%</td>
    <td style="white-space: nowrap; text-align: right">3173.72 ms</td>
    <td style="white-space: nowrap; text-align: right">3191.81 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap;text-align: right">209058.51</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">1815.47</td>
    <td style="white-space: nowrap; text-align: right">115.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">717.97</td>
    <td style="white-space: nowrap; text-align: right">291.18x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">305.48</td>
    <td style="white-space: nowrap; text-align: right">684.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">243.52</td>
    <td style="white-space: nowrap; text-align: right">858.48x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">97.99</td>
    <td style="white-space: nowrap; text-align: right">2133.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">32.58</td>
    <td style="white-space: nowrap; text-align: right">6416.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">25.86</td>
    <td style="white-space: nowrap; text-align: right">8083.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">2.02</td>
    <td style="white-space: nowrap; text-align: right">103410.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.89</td>
    <td style="white-space: nowrap; text-align: right">233635.76x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">274135.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.32</td>
    <td style="white-space: nowrap; text-align: right">662842.2x</td>
  </tr>

</table>