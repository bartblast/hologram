Benchmark

Hologram.Compiler.diff_module_info_plts/2

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
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">1858.32</td>
    <td style="white-space: nowrap; text-align: right">0.54 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.03%</td>
    <td style="white-space: nowrap; text-align: right">0.62 ms</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1616.13</td>
    <td style="white-space: nowrap; text-align: right">0.62 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.50%</td>
    <td style="white-space: nowrap; text-align: right">0.71 ms</td>
    <td style="white-space: nowrap; text-align: right">0.86 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">1273.18</td>
    <td style="white-space: nowrap; text-align: right">0.79 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.12%</td>
    <td style="white-space: nowrap; text-align: right">0.78 ms</td>
    <td style="white-space: nowrap; text-align: right">0.85 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">826.25</td>
    <td style="white-space: nowrap; text-align: right">1.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.05%</td>
    <td style="white-space: nowrap; text-align: right">1.20 ms</td>
    <td style="white-space: nowrap; text-align: right">1.32 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">822.59</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.25%</td>
    <td style="white-space: nowrap; text-align: right">1.21 ms</td>
    <td style="white-space: nowrap; text-align: right">1.46 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">820.39</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.48%</td>
    <td style="white-space: nowrap; text-align: right">1.21 ms</td>
    <td style="white-space: nowrap; text-align: right">1.33 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">816.52</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.06%</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">812.37</td>
    <td style="white-space: nowrap; text-align: right">1.23 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.74%</td>
    <td style="white-space: nowrap; text-align: right">1.22 ms</td>
    <td style="white-space: nowrap; text-align: right">1.41 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">774.03</td>
    <td style="white-space: nowrap; text-align: right">1.29 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.43%</td>
    <td style="white-space: nowrap; text-align: right">1.31 ms</td>
    <td style="white-space: nowrap; text-align: right">1.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">768.55</td>
    <td style="white-space: nowrap; text-align: right">1.30 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.94%</td>
    <td style="white-space: nowrap; text-align: right">1.31 ms</td>
    <td style="white-space: nowrap; text-align: right">1.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">764.02</td>
    <td style="white-space: nowrap; text-align: right">1.31 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.49%</td>
    <td style="white-space: nowrap; text-align: right">1.33 ms</td>
    <td style="white-space: nowrap; text-align: right">1.48 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">717.28</td>
    <td style="white-space: nowrap; text-align: right">1.39 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.42%</td>
    <td style="white-space: nowrap; text-align: right">1.41 ms</td>
    <td style="white-space: nowrap; text-align: right">1.57 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap;text-align: right">1858.32</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1616.13</td>
    <td style="white-space: nowrap; text-align: right">1.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">1273.18</td>
    <td style="white-space: nowrap; text-align: right">1.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">826.25</td>
    <td style="white-space: nowrap; text-align: right">2.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">822.59</td>
    <td style="white-space: nowrap; text-align: right">2.26x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">820.39</td>
    <td style="white-space: nowrap; text-align: right">2.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">816.52</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">812.37</td>
    <td style="white-space: nowrap; text-align: right">2.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">774.03</td>
    <td style="white-space: nowrap; text-align: right">2.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">768.55</td>
    <td style="white-space: nowrap; text-align: right">2.42x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">764.02</td>
    <td style="white-space: nowrap; text-align: right">2.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">717.28</td>
    <td style="white-space: nowrap; text-align: right">2.59x</td>
  </tr>

</table>