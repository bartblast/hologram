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
    <td style="white-space: nowrap; text-align: right">17733.43</td>
    <td style="white-space: nowrap; text-align: right">0.0564 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.76%</td>
    <td style="white-space: nowrap; text-align: right">0.0513 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0919 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">10980.55</td>
    <td style="white-space: nowrap; text-align: right">0.0911 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.24%</td>
    <td style="white-space: nowrap; text-align: right">0.0884 ms</td>
    <td style="white-space: nowrap; text-align: right">0.119 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">91.52</td>
    <td style="white-space: nowrap; text-align: right">10.93 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;96.67%</td>
    <td style="white-space: nowrap; text-align: right">4.12 ms</td>
    <td style="white-space: nowrap; text-align: right">27.26 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">82.97</td>
    <td style="white-space: nowrap; text-align: right">12.05 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;76.76%</td>
    <td style="white-space: nowrap; text-align: right">6.90 ms</td>
    <td style="white-space: nowrap; text-align: right">29.56 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">78.18</td>
    <td style="white-space: nowrap; text-align: right">12.79 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;65.49%</td>
    <td style="white-space: nowrap; text-align: right">9.01 ms</td>
    <td style="white-space: nowrap; text-align: right">33.07 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">44.10</td>
    <td style="white-space: nowrap; text-align: right">22.67 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;43.10%</td>
    <td style="white-space: nowrap; text-align: right">17.50 ms</td>
    <td style="white-space: nowrap; text-align: right">41.41 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">18.58</td>
    <td style="white-space: nowrap; text-align: right">53.83 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.12%</td>
    <td style="white-space: nowrap; text-align: right">50.19 ms</td>
    <td style="white-space: nowrap; text-align: right">71.67 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.25</td>
    <td style="white-space: nowrap; text-align: right">108.09 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.95%</td>
    <td style="white-space: nowrap; text-align: right">101.86 ms</td>
    <td style="white-space: nowrap; text-align: right">126.58 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">5.31</td>
    <td style="white-space: nowrap; text-align: right">188.48 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.70%</td>
    <td style="white-space: nowrap; text-align: right">187.78 ms</td>
    <td style="white-space: nowrap; text-align: right">218.36 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.52</td>
    <td style="white-space: nowrap; text-align: right">1917.03 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.44%</td>
    <td style="white-space: nowrap; text-align: right">1912.47 ms</td>
    <td style="white-space: nowrap; text-align: right">1957.76 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.51</td>
    <td style="white-space: nowrap; text-align: right">1954.29 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.73%</td>
    <td style="white-space: nowrap; text-align: right">1958.86 ms</td>
    <td style="white-space: nowrap; text-align: right">1970.03 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.147</td>
    <td style="white-space: nowrap; text-align: right">6779.83 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.65%</td>
    <td style="white-space: nowrap; text-align: right">6779.83 ms</td>
    <td style="white-space: nowrap; text-align: right">6811.00 ms</td>
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
    <td style="white-space: nowrap;text-align: right">17733.43</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">10980.55</td>
    <td style="white-space: nowrap; text-align: right">1.61x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">91.52</td>
    <td style="white-space: nowrap; text-align: right">193.76x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">82.97</td>
    <td style="white-space: nowrap; text-align: right">213.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">78.18</td>
    <td style="white-space: nowrap; text-align: right">226.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">44.10</td>
    <td style="white-space: nowrap; text-align: right">402.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">18.58</td>
    <td style="white-space: nowrap; text-align: right">954.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.25</td>
    <td style="white-space: nowrap; text-align: right">1916.86x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">5.31</td>
    <td style="white-space: nowrap; text-align: right">3342.33x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.52</td>
    <td style="white-space: nowrap; text-align: right">33995.56x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.51</td>
    <td style="white-space: nowrap; text-align: right">34656.31x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.147</td>
    <td style="white-space: nowrap; text-align: right">120229.58x</td>
  </tr>

</table>