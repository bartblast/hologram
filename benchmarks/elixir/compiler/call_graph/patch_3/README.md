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
    <td style="white-space: nowrap; text-align: right">20217.10</td>
    <td style="white-space: nowrap; text-align: right">0.0495 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.65%</td>
    <td style="white-space: nowrap; text-align: right">0.0503 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0640 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">146.57</td>
    <td style="white-space: nowrap; text-align: right">6.82 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;68.33%</td>
    <td style="white-space: nowrap; text-align: right">4.96 ms</td>
    <td style="white-space: nowrap; text-align: right">20.98 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">92.63</td>
    <td style="white-space: nowrap; text-align: right">10.80 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.06%</td>
    <td style="white-space: nowrap; text-align: right">10.25 ms</td>
    <td style="white-space: nowrap; text-align: right">18.09 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">56.46</td>
    <td style="white-space: nowrap; text-align: right">17.71 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;30.64%</td>
    <td style="white-space: nowrap; text-align: right">16.07 ms</td>
    <td style="white-space: nowrap; text-align: right">36.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">40.85</td>
    <td style="white-space: nowrap; text-align: right">24.48 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.98%</td>
    <td style="white-space: nowrap; text-align: right">22.23 ms</td>
    <td style="white-space: nowrap; text-align: right">37.87 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">27.67</td>
    <td style="white-space: nowrap; text-align: right">36.14 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.56%</td>
    <td style="white-space: nowrap; text-align: right">39.01 ms</td>
    <td style="white-space: nowrap; text-align: right">41.88 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.04</td>
    <td style="white-space: nowrap; text-align: right">99.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.06%</td>
    <td style="white-space: nowrap; text-align: right">97.78 ms</td>
    <td style="white-space: nowrap; text-align: right">113.57 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.13</td>
    <td style="white-space: nowrap; text-align: right">109.52 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.93%</td>
    <td style="white-space: nowrap; text-align: right">106.05 ms</td>
    <td style="white-space: nowrap; text-align: right">123.89 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.33</td>
    <td style="white-space: nowrap; text-align: right">300.53 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.12%</td>
    <td style="white-space: nowrap; text-align: right">299.35 ms</td>
    <td style="white-space: nowrap; text-align: right">344.11 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">1406.91 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.47%</td>
    <td style="white-space: nowrap; text-align: right">1402.87 ms</td>
    <td style="white-space: nowrap; text-align: right">1444.21 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.62</td>
    <td style="white-space: nowrap; text-align: right">1616.10 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.51%</td>
    <td style="white-space: nowrap; text-align: right">1608.12 ms</td>
    <td style="white-space: nowrap; text-align: right">1665.06 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.189</td>
    <td style="white-space: nowrap; text-align: right">5280.96 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">5280.96 ms</td>
    <td style="white-space: nowrap; text-align: right">5281.00 ms</td>
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
    <td style="white-space: nowrap;text-align: right">20217.10</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">146.57</td>
    <td style="white-space: nowrap; text-align: right">137.94x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">92.63</td>
    <td style="white-space: nowrap; text-align: right">218.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">56.46</td>
    <td style="white-space: nowrap; text-align: right">358.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">40.85</td>
    <td style="white-space: nowrap; text-align: right">494.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">27.67</td>
    <td style="white-space: nowrap; text-align: right">730.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">10.04</td>
    <td style="white-space: nowrap; text-align: right">2013.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.13</td>
    <td style="white-space: nowrap; text-align: right">2214.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.33</td>
    <td style="white-space: nowrap; text-align: right">6075.9x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">28443.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.62</td>
    <td style="white-space: nowrap; text-align: right">32672.92x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.189</td>
    <td style="white-space: nowrap; text-align: right">106765.73x</td>
  </tr>

</table>