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
    <td style="white-space: nowrap; text-align: right">22751.01</td>
    <td style="white-space: nowrap; text-align: right">0.0440 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.70%</td>
    <td style="white-space: nowrap; text-align: right">0.0424 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0564 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">132.79</td>
    <td style="white-space: nowrap; text-align: right">7.53 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;59.80%</td>
    <td style="white-space: nowrap; text-align: right">5.07 ms</td>
    <td style="white-space: nowrap; text-align: right">19.63 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">115.04</td>
    <td style="white-space: nowrap; text-align: right">8.69 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.10%</td>
    <td style="white-space: nowrap; text-align: right">8.48 ms</td>
    <td style="white-space: nowrap; text-align: right">10.84 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">57.83</td>
    <td style="white-space: nowrap; text-align: right">17.29 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.62%</td>
    <td style="white-space: nowrap; text-align: right">14.55 ms</td>
    <td style="white-space: nowrap; text-align: right">29.34 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">47.67</td>
    <td style="white-space: nowrap; text-align: right">20.98 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.31%</td>
    <td style="white-space: nowrap; text-align: right">19.18 ms</td>
    <td style="white-space: nowrap; text-align: right">33.60 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">31.92</td>
    <td style="white-space: nowrap; text-align: right">31.33 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.46%</td>
    <td style="white-space: nowrap; text-align: right">33.33 ms</td>
    <td style="white-space: nowrap; text-align: right">39.20 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">11.57</td>
    <td style="white-space: nowrap; text-align: right">86.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.03%</td>
    <td style="white-space: nowrap; text-align: right">85.39 ms</td>
    <td style="white-space: nowrap; text-align: right">98.43 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.98</td>
    <td style="white-space: nowrap; text-align: right">100.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.06%</td>
    <td style="white-space: nowrap; text-align: right">97.71 ms</td>
    <td style="white-space: nowrap; text-align: right">112.14 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.63</td>
    <td style="white-space: nowrap; text-align: right">275.69 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.13%</td>
    <td style="white-space: nowrap; text-align: right">272.34 ms</td>
    <td style="white-space: nowrap; text-align: right">329.95 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">1307.56 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.46%</td>
    <td style="white-space: nowrap; text-align: right">1305.27 ms</td>
    <td style="white-space: nowrap; text-align: right">1319.59 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.68</td>
    <td style="white-space: nowrap; text-align: right">1472.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.43%</td>
    <td style="white-space: nowrap; text-align: right">1472.37 ms</td>
    <td style="white-space: nowrap; text-align: right">1482.58 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.20</td>
    <td style="white-space: nowrap; text-align: right">4939.73 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.14%</td>
    <td style="white-space: nowrap; text-align: right">4939.73 ms</td>
    <td style="white-space: nowrap; text-align: right">4944.58 ms</td>
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
    <td style="white-space: nowrap;text-align: right">22751.01</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">132.79</td>
    <td style="white-space: nowrap; text-align: right">171.33x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">115.04</td>
    <td style="white-space: nowrap; text-align: right">197.77x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">57.83</td>
    <td style="white-space: nowrap; text-align: right">393.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">47.67</td>
    <td style="white-space: nowrap; text-align: right">477.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">31.92</td>
    <td style="white-space: nowrap; text-align: right">712.83x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">11.57</td>
    <td style="white-space: nowrap; text-align: right">1967.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.98</td>
    <td style="white-space: nowrap; text-align: right">2279.91x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.63</td>
    <td style="white-space: nowrap; text-align: right">6272.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">29748.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.68</td>
    <td style="white-space: nowrap; text-align: right">33494.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.20</td>
    <td style="white-space: nowrap; text-align: right">112383.91x</td>
  </tr>

</table>