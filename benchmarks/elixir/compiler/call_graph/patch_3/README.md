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
    <td style="white-space: nowrap; text-align: right">21633.66</td>
    <td style="white-space: nowrap; text-align: right">0.0462 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.23%</td>
    <td style="white-space: nowrap; text-align: right">0.0451 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0644 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">105.25</td>
    <td style="white-space: nowrap; text-align: right">9.50 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.41%</td>
    <td style="white-space: nowrap; text-align: right">8.85 ms</td>
    <td style="white-space: nowrap; text-align: right">14.99 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">103.65</td>
    <td style="white-space: nowrap; text-align: right">9.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;62.29%</td>
    <td style="white-space: nowrap; text-align: right">6.08 ms</td>
    <td style="white-space: nowrap; text-align: right">22.44 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">49.56</td>
    <td style="white-space: nowrap; text-align: right">20.18 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.90%</td>
    <td style="white-space: nowrap; text-align: right">16.52 ms</td>
    <td style="white-space: nowrap; text-align: right">33.54 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">44.65</td>
    <td style="white-space: nowrap; text-align: right">22.40 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.79%</td>
    <td style="white-space: nowrap; text-align: right">21.04 ms</td>
    <td style="white-space: nowrap; text-align: right">40.11 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">33.26</td>
    <td style="white-space: nowrap; text-align: right">30.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.58%</td>
    <td style="white-space: nowrap; text-align: right">28.26 ms</td>
    <td style="white-space: nowrap; text-align: right">41.82 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.55</td>
    <td style="white-space: nowrap; text-align: right">94.82 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.38%</td>
    <td style="white-space: nowrap; text-align: right">92.17 ms</td>
    <td style="white-space: nowrap; text-align: right">106.96 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.40</td>
    <td style="white-space: nowrap; text-align: right">106.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.37%</td>
    <td style="white-space: nowrap; text-align: right">105.36 ms</td>
    <td style="white-space: nowrap; text-align: right">129.05 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.54</td>
    <td style="white-space: nowrap; text-align: right">282.72 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.24%</td>
    <td style="white-space: nowrap; text-align: right">283.69 ms</td>
    <td style="white-space: nowrap; text-align: right">314.68 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">1333.10 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.48%</td>
    <td style="white-space: nowrap; text-align: right">1332.71 ms</td>
    <td style="white-space: nowrap; text-align: right">1343.11 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.65</td>
    <td style="white-space: nowrap; text-align: right">1530.37 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.34%</td>
    <td style="white-space: nowrap; text-align: right">1519.30 ms</td>
    <td style="white-space: nowrap; text-align: right">1578.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.190</td>
    <td style="white-space: nowrap; text-align: right">5251.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.00%</td>
    <td style="white-space: nowrap; text-align: right">5251.49 ms</td>
    <td style="white-space: nowrap; text-align: right">5325.62 ms</td>
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
    <td style="white-space: nowrap;text-align: right">21633.66</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">105.25</td>
    <td style="white-space: nowrap; text-align: right">205.54x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">103.65</td>
    <td style="white-space: nowrap; text-align: right">208.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">49.56</td>
    <td style="white-space: nowrap; text-align: right">436.48x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">44.65</td>
    <td style="white-space: nowrap; text-align: right">484.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">33.26</td>
    <td style="white-space: nowrap; text-align: right">650.47x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.55</td>
    <td style="white-space: nowrap; text-align: right">2051.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.40</td>
    <td style="white-space: nowrap; text-align: right">2300.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.54</td>
    <td style="white-space: nowrap; text-align: right">6116.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.75</td>
    <td style="white-space: nowrap; text-align: right">28839.89x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.65</td>
    <td style="white-space: nowrap; text-align: right">33107.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.190</td>
    <td style="white-space: nowrap; text-align: right">113608.96x</td>
  </tr>

</table>