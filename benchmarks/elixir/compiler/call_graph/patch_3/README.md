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
    <td style="white-space: nowrap; text-align: right">230273.26</td>
    <td style="white-space: nowrap; text-align: right">0.00434 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.36%</td>
    <td style="white-space: nowrap; text-align: right">0.00429 ms</td>
    <td style="white-space: nowrap; text-align: right">0.00475 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">797.37</td>
    <td style="white-space: nowrap; text-align: right">1.25 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.05%</td>
    <td style="white-space: nowrap; text-align: right">1.25 ms</td>
    <td style="white-space: nowrap; text-align: right">1.33 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">206.23</td>
    <td style="white-space: nowrap; text-align: right">4.85 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.34%</td>
    <td style="white-space: nowrap; text-align: right">4.67 ms</td>
    <td style="white-space: nowrap; text-align: right">5.82 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">136.98</td>
    <td style="white-space: nowrap; text-align: right">7.30 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.19%</td>
    <td style="white-space: nowrap; text-align: right">7.24 ms</td>
    <td style="white-space: nowrap; text-align: right">7.61 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">122.87</td>
    <td style="white-space: nowrap; text-align: right">8.14 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.52%</td>
    <td style="white-space: nowrap; text-align: right">8.08 ms</td>
    <td style="white-space: nowrap; text-align: right">8.78 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">74.85</td>
    <td style="white-space: nowrap; text-align: right">13.36 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.30%</td>
    <td style="white-space: nowrap; text-align: right">13.36 ms</td>
    <td style="white-space: nowrap; text-align: right">15.52 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">31.37</td>
    <td style="white-space: nowrap; text-align: right">31.88 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.81%</td>
    <td style="white-space: nowrap; text-align: right">31.78 ms</td>
    <td style="white-space: nowrap; text-align: right">33.46 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">20.91</td>
    <td style="white-space: nowrap; text-align: right">47.81 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.59%</td>
    <td style="white-space: nowrap; text-align: right">47.82 ms</td>
    <td style="white-space: nowrap; text-align: right">50.27 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1.45</td>
    <td style="white-space: nowrap; text-align: right">689.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.04%</td>
    <td style="white-space: nowrap; text-align: right">682.57 ms</td>
    <td style="white-space: nowrap; text-align: right">807.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">1308.93 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.19%</td>
    <td style="white-space: nowrap; text-align: right">1313.80 ms</td>
    <td style="white-space: nowrap; text-align: right">1322.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">1336.97 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.71%</td>
    <td style="white-space: nowrap; text-align: right">1340.43 ms</td>
    <td style="white-space: nowrap; text-align: right">1348.08 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.31</td>
    <td style="white-space: nowrap; text-align: right">3184.44 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.51%</td>
    <td style="white-space: nowrap; text-align: right">3186.99 ms</td>
    <td style="white-space: nowrap; text-align: right">3199.37 ms</td>
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
    <td style="white-space: nowrap;text-align: right">230273.26</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">797.37</td>
    <td style="white-space: nowrap; text-align: right">288.79x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">206.23</td>
    <td style="white-space: nowrap; text-align: right">1116.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">136.98</td>
    <td style="white-space: nowrap; text-align: right">1681.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">122.87</td>
    <td style="white-space: nowrap; text-align: right">1874.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">74.85</td>
    <td style="white-space: nowrap; text-align: right">3076.33x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">31.37</td>
    <td style="white-space: nowrap; text-align: right">7341.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">20.91</td>
    <td style="white-space: nowrap; text-align: right">11010.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1.45</td>
    <td style="white-space: nowrap; text-align: right">158689.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.76</td>
    <td style="white-space: nowrap; text-align: right">301410.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">307868.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.31</td>
    <td style="white-space: nowrap; text-align: right">733291.23x</td>
  </tr>

</table>