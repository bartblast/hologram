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
    <td style="white-space: nowrap; text-align: right">1532.24</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.55%</td>
    <td style="white-space: nowrap; text-align: right">0.64 ms</td>
    <td style="white-space: nowrap; text-align: right">0.90 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1363.57</td>
    <td style="white-space: nowrap; text-align: right">0.73 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.80%</td>
    <td style="white-space: nowrap; text-align: right">0.72 ms</td>
    <td style="white-space: nowrap; text-align: right">0.99 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">939.69</td>
    <td style="white-space: nowrap; text-align: right">1.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.44%</td>
    <td style="white-space: nowrap; text-align: right">1.13 ms</td>
    <td style="white-space: nowrap; text-align: right">1.49 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">693.29</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.84%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">1.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">692.18</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.06%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">1.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">691.66</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.92%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">1.54 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">687.67</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.03%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">1.62 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">673.41</td>
    <td style="white-space: nowrap; text-align: right">1.48 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.98%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">2.01 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">673.02</td>
    <td style="white-space: nowrap; text-align: right">1.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.88%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">2.01 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">671.22</td>
    <td style="white-space: nowrap; text-align: right">1.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.89%</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
    <td style="white-space: nowrap; text-align: right">1.99 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">668.68</td>
    <td style="white-space: nowrap; text-align: right">1.50 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.29%</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
    <td style="white-space: nowrap; text-align: right">2.02 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">665.11</td>
    <td style="white-space: nowrap; text-align: right">1.50 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.53%</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
    <td style="white-space: nowrap; text-align: right">2.03 ms</td>
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
    <td style="white-space: nowrap;text-align: right">1532.24</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">1363.57</td>
    <td style="white-space: nowrap; text-align: right">1.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">939.69</td>
    <td style="white-space: nowrap; text-align: right">1.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">693.29</td>
    <td style="white-space: nowrap; text-align: right">2.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">692.18</td>
    <td style="white-space: nowrap; text-align: right">2.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">691.66</td>
    <td style="white-space: nowrap; text-align: right">2.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">687.67</td>
    <td style="white-space: nowrap; text-align: right">2.23x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">673.41</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">673.02</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">671.22</td>
    <td style="white-space: nowrap; text-align: right">2.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">668.68</td>
    <td style="white-space: nowrap; text-align: right">2.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">665.11</td>
    <td style="white-space: nowrap; text-align: right">2.3x</td>
  </tr>

</table>