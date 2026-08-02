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
    <td style="white-space: nowrap; text-align: right">134873.72</td>
    <td style="white-space: nowrap; text-align: right">0.00741 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.69%</td>
    <td style="white-space: nowrap; text-align: right">0.00717 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0110 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2228.84</td>
    <td style="white-space: nowrap; text-align: right">0.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.57%</td>
    <td style="white-space: nowrap; text-align: right">0.44 ms</td>
    <td style="white-space: nowrap; text-align: right">0.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">64.72</td>
    <td style="white-space: nowrap; text-align: right">15.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.78%</td>
    <td style="white-space: nowrap; text-align: right">16.61 ms</td>
    <td style="white-space: nowrap; text-align: right">19.30 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">60.94</td>
    <td style="white-space: nowrap; text-align: right">16.41 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.42%</td>
    <td style="white-space: nowrap; text-align: right">17.64 ms</td>
    <td style="white-space: nowrap; text-align: right">21.32 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">59.26</td>
    <td style="white-space: nowrap; text-align: right">16.88 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.42%</td>
    <td style="white-space: nowrap; text-align: right">17.88 ms</td>
    <td style="white-space: nowrap; text-align: right">21.07 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">39.26</td>
    <td style="white-space: nowrap; text-align: right">25.47 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.74%</td>
    <td style="white-space: nowrap; text-align: right">25.84 ms</td>
    <td style="white-space: nowrap; text-align: right">30.60 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">19.88</td>
    <td style="white-space: nowrap; text-align: right">50.31 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.17%</td>
    <td style="white-space: nowrap; text-align: right">49.37 ms</td>
    <td style="white-space: nowrap; text-align: right">87.29 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.83</td>
    <td style="white-space: nowrap; text-align: right">77.92 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.12%</td>
    <td style="white-space: nowrap; text-align: right">79.42 ms</td>
    <td style="white-space: nowrap; text-align: right">89.02 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.18</td>
    <td style="white-space: nowrap; text-align: right">239.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.37%</td>
    <td style="white-space: nowrap; text-align: right">240.10 ms</td>
    <td style="white-space: nowrap; text-align: right">269.94 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.70</td>
    <td style="white-space: nowrap; text-align: right">1431.30 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.71%</td>
    <td style="white-space: nowrap; text-align: right">1433.59 ms</td>
    <td style="white-space: nowrap; text-align: right">1443.93 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.62</td>
    <td style="white-space: nowrap; text-align: right">1608.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.50%</td>
    <td style="white-space: nowrap; text-align: right">1616.60 ms</td>
    <td style="white-space: nowrap; text-align: right">1675.54 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">4118.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.54%</td>
    <td style="white-space: nowrap; text-align: right">4159.59 ms</td>
    <td style="white-space: nowrap; text-align: right">4195.52 ms</td>
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
    <td style="white-space: nowrap;text-align: right">134873.72</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2228.84</td>
    <td style="white-space: nowrap; text-align: right">60.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">64.72</td>
    <td style="white-space: nowrap; text-align: right">2083.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">60.94</td>
    <td style="white-space: nowrap; text-align: right">2213.26x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">59.26</td>
    <td style="white-space: nowrap; text-align: right">2276.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">39.26</td>
    <td style="white-space: nowrap; text-align: right">3435.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">19.88</td>
    <td style="white-space: nowrap; text-align: right">6785.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.83</td>
    <td style="white-space: nowrap; text-align: right">10509.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.18</td>
    <td style="white-space: nowrap; text-align: right">32280.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.70</td>
    <td style="white-space: nowrap; text-align: right">193044.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.62</td>
    <td style="white-space: nowrap; text-align: right">216989.93x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">555427.27x</td>
  </tr>

</table>