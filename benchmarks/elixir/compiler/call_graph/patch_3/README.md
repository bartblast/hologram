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
    <td style="white-space: nowrap; text-align: right">141105.70</td>
    <td style="white-space: nowrap; text-align: right">0.00709 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.68%</td>
    <td style="white-space: nowrap; text-align: right">0.00679 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0105 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2487.27</td>
    <td style="white-space: nowrap; text-align: right">0.40 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.58%</td>
    <td style="white-space: nowrap; text-align: right">0.39 ms</td>
    <td style="white-space: nowrap; text-align: right">0.50 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">71.27</td>
    <td style="white-space: nowrap; text-align: right">14.03 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;33.54%</td>
    <td style="white-space: nowrap; text-align: right">15.49 ms</td>
    <td style="white-space: nowrap; text-align: right">21.49 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">62.25</td>
    <td style="white-space: nowrap; text-align: right">16.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.04%</td>
    <td style="white-space: nowrap; text-align: right">17.55 ms</td>
    <td style="white-space: nowrap; text-align: right">20.04 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">59.55</td>
    <td style="white-space: nowrap; text-align: right">16.79 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.53%</td>
    <td style="white-space: nowrap; text-align: right">17.94 ms</td>
    <td style="white-space: nowrap; text-align: right">22.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">38.03</td>
    <td style="white-space: nowrap; text-align: right">26.30 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.63%</td>
    <td style="white-space: nowrap; text-align: right">26.86 ms</td>
    <td style="white-space: nowrap; text-align: right">31.60 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">21.58</td>
    <td style="white-space: nowrap; text-align: right">46.35 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.27%</td>
    <td style="white-space: nowrap; text-align: right">47.50 ms</td>
    <td style="white-space: nowrap; text-align: right">50.21 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.12</td>
    <td style="white-space: nowrap; text-align: right">82.50 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.14%</td>
    <td style="white-space: nowrap; text-align: right">83.29 ms</td>
    <td style="white-space: nowrap; text-align: right">91.70 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.09</td>
    <td style="white-space: nowrap; text-align: right">244.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.49%</td>
    <td style="white-space: nowrap; text-align: right">240.56 ms</td>
    <td style="white-space: nowrap; text-align: right">282.03 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">1416.15 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.17%</td>
    <td style="white-space: nowrap; text-align: right">1410.23 ms</td>
    <td style="white-space: nowrap; text-align: right">1446.96 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.63</td>
    <td style="white-space: nowrap; text-align: right">1580.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.54%</td>
    <td style="white-space: nowrap; text-align: right">1562.13 ms</td>
    <td style="white-space: nowrap; text-align: right">1656.03 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.26</td>
    <td style="white-space: nowrap; text-align: right">3860.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.37%</td>
    <td style="white-space: nowrap; text-align: right">3859.36 ms</td>
    <td style="white-space: nowrap; text-align: right">3952.10 ms</td>
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
    <td style="white-space: nowrap;text-align: right">141105.70</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2487.27</td>
    <td style="white-space: nowrap; text-align: right">56.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">71.27</td>
    <td style="white-space: nowrap; text-align: right">1979.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">62.25</td>
    <td style="white-space: nowrap; text-align: right">2266.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">59.55</td>
    <td style="white-space: nowrap; text-align: right">2369.7x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">38.03</td>
    <td style="white-space: nowrap; text-align: right">3710.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">21.58</td>
    <td style="white-space: nowrap; text-align: right">6540.19x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.12</td>
    <td style="white-space: nowrap; text-align: right">11641.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.09</td>
    <td style="white-space: nowrap; text-align: right">34494.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">199826.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.63</td>
    <td style="white-space: nowrap; text-align: right">223007.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.26</td>
    <td style="white-space: nowrap; text-align: right">544697.66x</td>
  </tr>

</table>