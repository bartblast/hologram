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
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">129032.75</td>
    <td style="white-space: nowrap; text-align: right">0.00775 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.30%</td>
    <td style="white-space: nowrap; text-align: right">0.00729 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0153 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2311.25</td>
    <td style="white-space: nowrap; text-align: right">0.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.60%</td>
    <td style="white-space: nowrap; text-align: right">0.43 ms</td>
    <td style="white-space: nowrap; text-align: right">0.49 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">80.47</td>
    <td style="white-space: nowrap; text-align: right">12.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;25.31%</td>
    <td style="white-space: nowrap; text-align: right">13.63 ms</td>
    <td style="white-space: nowrap; text-align: right">16.05 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">74.77</td>
    <td style="white-space: nowrap; text-align: right">13.37 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.34%</td>
    <td style="white-space: nowrap; text-align: right">14.89 ms</td>
    <td style="white-space: nowrap; text-align: right">17.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">67.03</td>
    <td style="white-space: nowrap; text-align: right">14.92 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.91%</td>
    <td style="white-space: nowrap; text-align: right">15.01 ms</td>
    <td style="white-space: nowrap; text-align: right">18.75 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">43.44</td>
    <td style="white-space: nowrap; text-align: right">23.02 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.21%</td>
    <td style="white-space: nowrap; text-align: right">23.42 ms</td>
    <td style="white-space: nowrap; text-align: right">27.42 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">22.85</td>
    <td style="white-space: nowrap; text-align: right">43.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.85%</td>
    <td style="white-space: nowrap; text-align: right">43.98 ms</td>
    <td style="white-space: nowrap; text-align: right">49.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">13.62</td>
    <td style="white-space: nowrap; text-align: right">73.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.04%</td>
    <td style="white-space: nowrap; text-align: right">74.18 ms</td>
    <td style="white-space: nowrap; text-align: right">82.63 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.17</td>
    <td style="white-space: nowrap; text-align: right">240.04 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.68%</td>
    <td style="white-space: nowrap; text-align: right">239.14 ms</td>
    <td style="white-space: nowrap; text-align: right">254.60 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.72</td>
    <td style="white-space: nowrap; text-align: right">1387.87 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.65%</td>
    <td style="white-space: nowrap; text-align: right">1387.13 ms</td>
    <td style="white-space: nowrap; text-align: right">1398.38 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.63</td>
    <td style="white-space: nowrap; text-align: right">1575.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.95%</td>
    <td style="white-space: nowrap; text-align: right">1566.98 ms</td>
    <td style="white-space: nowrap; text-align: right">1643.63 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.28</td>
    <td style="white-space: nowrap; text-align: right">3632.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.31%</td>
    <td style="white-space: nowrap; text-align: right">3634.82 ms</td>
    <td style="white-space: nowrap; text-align: right">3642.58 ms</td>
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
    <td style="white-space: nowrap;text-align: right">129032.75</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2311.25</td>
    <td style="white-space: nowrap; text-align: right">55.83x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">80.47</td>
    <td style="white-space: nowrap; text-align: right">1603.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">74.77</td>
    <td style="white-space: nowrap; text-align: right">1725.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">67.03</td>
    <td style="white-space: nowrap; text-align: right">1924.98x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">43.44</td>
    <td style="white-space: nowrap; text-align: right">2970.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">22.85</td>
    <td style="white-space: nowrap; text-align: right">5646.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">13.62</td>
    <td style="white-space: nowrap; text-align: right">9477.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.17</td>
    <td style="white-space: nowrap; text-align: right">30972.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.72</td>
    <td style="white-space: nowrap; text-align: right">179081.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.63</td>
    <td style="white-space: nowrap; text-align: right">203334.56x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.28</td>
    <td style="white-space: nowrap; text-align: right">468732.6x</td>
  </tr>

</table>