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
    <td style="white-space: nowrap; text-align: right">20460.52</td>
    <td style="white-space: nowrap; text-align: right">0.0489 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.30%</td>
    <td style="white-space: nowrap; text-align: right">0.0469 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0918 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">9421.70</td>
    <td style="white-space: nowrap; text-align: right">0.106 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.25%</td>
    <td style="white-space: nowrap; text-align: right">0.0949 ms</td>
    <td style="white-space: nowrap; text-align: right">0.24 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">41.27</td>
    <td style="white-space: nowrap; text-align: right">24.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;38.54%</td>
    <td style="white-space: nowrap; text-align: right">23.71 ms</td>
    <td style="white-space: nowrap; text-align: right">41.47 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">39.54</td>
    <td style="white-space: nowrap; text-align: right">25.29 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;42.86%</td>
    <td style="white-space: nowrap; text-align: right">24.70 ms</td>
    <td style="white-space: nowrap; text-align: right">46.64 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">30.09</td>
    <td style="white-space: nowrap; text-align: right">33.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.77%</td>
    <td style="white-space: nowrap; text-align: right">33.75 ms</td>
    <td style="white-space: nowrap; text-align: right">43.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">28.05</td>
    <td style="white-space: nowrap; text-align: right">35.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;36.51%</td>
    <td style="white-space: nowrap; text-align: right">38.14 ms</td>
    <td style="white-space: nowrap; text-align: right">60.89 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.03</td>
    <td style="white-space: nowrap; text-align: right">99.71 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.48%</td>
    <td style="white-space: nowrap; text-align: right">97.46 ms</td>
    <td style="white-space: nowrap; text-align: right">160.24 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.44</td>
    <td style="white-space: nowrap; text-align: right">105.89 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.61%</td>
    <td style="white-space: nowrap; text-align: right">101.90 ms</td>
    <td style="white-space: nowrap; text-align: right">175.89 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">7.85</td>
    <td style="white-space: nowrap; text-align: right">127.38 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.98%</td>
    <td style="white-space: nowrap; text-align: right">125.76 ms</td>
    <td style="white-space: nowrap; text-align: right">144.57 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">1339.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.68%</td>
    <td style="white-space: nowrap; text-align: right">1342.38 ms</td>
    <td style="white-space: nowrap; text-align: right">1364.38 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.72</td>
    <td style="white-space: nowrap; text-align: right">1379.36 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.12%</td>
    <td style="white-space: nowrap; text-align: right">1376.72 ms</td>
    <td style="white-space: nowrap; text-align: right">1407.89 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.20</td>
    <td style="white-space: nowrap; text-align: right">4929.75 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">4929.75 ms</td>
    <td style="white-space: nowrap; text-align: right">4929.89 ms</td>
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
    <td style="white-space: nowrap;text-align: right">20460.52</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">9421.70</td>
    <td style="white-space: nowrap; text-align: right">2.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">41.27</td>
    <td style="white-space: nowrap; text-align: right">495.79x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">39.54</td>
    <td style="white-space: nowrap; text-align: right">517.48x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">30.09</td>
    <td style="white-space: nowrap; text-align: right">679.87x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">28.05</td>
    <td style="white-space: nowrap; text-align: right">729.42x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.03</td>
    <td style="white-space: nowrap; text-align: right">2040.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.44</td>
    <td style="white-space: nowrap; text-align: right">2166.56x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">7.85</td>
    <td style="white-space: nowrap; text-align: right">2606.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">27401.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.72</td>
    <td style="white-space: nowrap; text-align: right">28222.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.20</td>
    <td style="white-space: nowrap; text-align: right">100865.32x</td>
  </tr>

</table>