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
    <td style="white-space: nowrap; text-align: right">244535.79</td>
    <td style="white-space: nowrap; text-align: right">0.00409 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.15%</td>
    <td style="white-space: nowrap; text-align: right">0.00400 ms</td>
    <td style="white-space: nowrap; text-align: right">0.00671 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">1886.53</td>
    <td style="white-space: nowrap; text-align: right">0.53 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.16%</td>
    <td style="white-space: nowrap; text-align: right">0.53 ms</td>
    <td style="white-space: nowrap; text-align: right">0.56 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">530.03</td>
    <td style="white-space: nowrap; text-align: right">1.89 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.37%</td>
    <td style="white-space: nowrap; text-align: right">1.87 ms</td>
    <td style="white-space: nowrap; text-align: right">2.03 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">292.51</td>
    <td style="white-space: nowrap; text-align: right">3.42 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.52%</td>
    <td style="white-space: nowrap; text-align: right">3.30 ms</td>
    <td style="white-space: nowrap; text-align: right">3.87 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">211.50</td>
    <td style="white-space: nowrap; text-align: right">4.73 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.52%</td>
    <td style="white-space: nowrap; text-align: right">4.67 ms</td>
    <td style="white-space: nowrap; text-align: right">5.65 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">97.67</td>
    <td style="white-space: nowrap; text-align: right">10.24 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.53%</td>
    <td style="white-space: nowrap; text-align: right">10.20 ms</td>
    <td style="white-space: nowrap; text-align: right">10.62 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">33.62</td>
    <td style="white-space: nowrap; text-align: right">29.74 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.14%</td>
    <td style="white-space: nowrap; text-align: right">29.66 ms</td>
    <td style="white-space: nowrap; text-align: right">30.81 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">26.31</td>
    <td style="white-space: nowrap; text-align: right">38.00 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.52%</td>
    <td style="white-space: nowrap; text-align: right">37.96 ms</td>
    <td style="white-space: nowrap; text-align: right">39.35 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">2.04</td>
    <td style="white-space: nowrap; text-align: right">489.16 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.65%</td>
    <td style="white-space: nowrap; text-align: right">489.20 ms</td>
    <td style="white-space: nowrap; text-align: right">495.57 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.86</td>
    <td style="white-space: nowrap; text-align: right">1168.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.34%</td>
    <td style="white-space: nowrap; text-align: right">1138.06 ms</td>
    <td style="white-space: nowrap; text-align: right">1306.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.77</td>
    <td style="white-space: nowrap; text-align: right">1303.94 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.00%</td>
    <td style="white-space: nowrap; text-align: right">1301.56 ms</td>
    <td style="white-space: nowrap; text-align: right">1323.54 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.32</td>
    <td style="white-space: nowrap; text-align: right">3153.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.09%</td>
    <td style="white-space: nowrap; text-align: right">3108.66 ms</td>
    <td style="white-space: nowrap; text-align: right">3265.48 ms</td>
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
    <td style="white-space: nowrap;text-align: right">244535.79</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">1886.53</td>
    <td style="white-space: nowrap; text-align: right">129.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">530.03</td>
    <td style="white-space: nowrap; text-align: right">461.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">292.51</td>
    <td style="white-space: nowrap; text-align: right">836.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">211.50</td>
    <td style="white-space: nowrap; text-align: right">1156.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">97.67</td>
    <td style="white-space: nowrap; text-align: right">2503.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">33.62</td>
    <td style="white-space: nowrap; text-align: right">7273.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">26.31</td>
    <td style="white-space: nowrap; text-align: right">9293.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">2.04</td>
    <td style="white-space: nowrap; text-align: right">119617.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.86</td>
    <td style="white-space: nowrap; text-align: right">285632.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.77</td>
    <td style="white-space: nowrap; text-align: right">318860.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.32</td>
    <td style="white-space: nowrap; text-align: right">771207.83x</td>
  </tr>

</table>