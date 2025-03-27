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
    <td style="white-space: nowrap">1.16.1</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">26.2.2</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">1 min</td>
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
    <td style="white-space: nowrap; text-align: right">261778.73</td>
    <td style="white-space: nowrap; text-align: right">0.00382 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.12%</td>
    <td style="white-space: nowrap; text-align: right">0.00358 ms</td>
    <td style="white-space: nowrap; text-align: right">0.00633 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">957.64</td>
    <td style="white-space: nowrap; text-align: right">1.04 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.85%</td>
    <td style="white-space: nowrap; text-align: right">1.00 ms</td>
    <td style="white-space: nowrap; text-align: right">1.35 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">6.10</td>
    <td style="white-space: nowrap; text-align: right">164.04 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.26%</td>
    <td style="white-space: nowrap; text-align: right">163.96 ms</td>
    <td style="white-space: nowrap; text-align: right">169.33 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">2.70</td>
    <td style="white-space: nowrap; text-align: right">369.87 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.71%</td>
    <td style="white-space: nowrap; text-align: right">370.23 ms</td>
    <td style="white-space: nowrap; text-align: right">385.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.69</td>
    <td style="white-space: nowrap; text-align: right">371.56 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.20%</td>
    <td style="white-space: nowrap; text-align: right">369.06 ms</td>
    <td style="white-space: nowrap; text-align: right">392.05 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated </td>
    <td style="white-space: nowrap; text-align: right">2.67</td>
    <td style="white-space: nowrap; text-align: right">374.11 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.20%</td>
    <td style="white-space: nowrap; text-align: right">374.29 ms</td>
    <td style="white-space: nowrap; text-align: right">389.86 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1.95</td>
    <td style="white-space: nowrap; text-align: right">512.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.81%</td>
    <td style="white-space: nowrap; text-align: right">509.11 ms</td>
    <td style="white-space: nowrap; text-align: right">617.38 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">0.60</td>
    <td style="white-space: nowrap; text-align: right">1675.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.78%</td>
    <td style="white-space: nowrap; text-align: right">1674.53 ms</td>
    <td style="white-space: nowrap; text-align: right">1702.81 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">0.45</td>
    <td style="white-space: nowrap; text-align: right">2227.18 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.69%</td>
    <td style="white-space: nowrap; text-align: right">2227.90 ms</td>
    <td style="white-space: nowrap; text-align: right">2282.96 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">0.0198</td>
    <td style="white-space: nowrap; text-align: right">50555.33 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.77%</td>
    <td style="white-space: nowrap; text-align: right">50555.33 ms</td>
    <td style="white-space: nowrap; text-align: right">51188.47 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.0124</td>
    <td style="white-space: nowrap; text-align: right">80508.68 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">80508.68 ms</td>
    <td style="white-space: nowrap; text-align: right">80508.68 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">0.00796</td>
    <td style="white-space: nowrap; text-align: right">125559.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">125559.84 ms</td>
    <td style="white-space: nowrap; text-align: right">125559.84 ms</td>
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
    <td style="white-space: nowrap;text-align: right">261778.73</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">957.64</td>
    <td style="white-space: nowrap; text-align: right">273.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">6.10</td>
    <td style="white-space: nowrap; text-align: right">42940.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">2.70</td>
    <td style="white-space: nowrap; text-align: right">96824.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.69</td>
    <td style="white-space: nowrap; text-align: right">97267.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated </td>
    <td style="white-space: nowrap; text-align: right">2.67</td>
    <td style="white-space: nowrap; text-align: right">97935.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1.95</td>
    <td style="white-space: nowrap; text-align: right">134152.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">0.60</td>
    <td style="white-space: nowrap; text-align: right">438534.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">0.45</td>
    <td style="white-space: nowrap; text-align: right">583029.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">0.0198</td>
    <td style="white-space: nowrap; text-align: right">13234311.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.0124</td>
    <td style="white-space: nowrap; text-align: right">21075459.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">0.00796</td>
    <td style="white-space: nowrap; text-align: right">32868894.88x</td>
  </tr>

</table>