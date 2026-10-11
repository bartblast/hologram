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
    <td style="white-space: nowrap; text-align: right">20558.38</td>
    <td style="white-space: nowrap; text-align: right">0.0486 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.98%</td>
    <td style="white-space: nowrap; text-align: right">0.0482 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0577 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">9879.06</td>
    <td style="white-space: nowrap; text-align: right">0.101 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.41%</td>
    <td style="white-space: nowrap; text-align: right">0.0991 ms</td>
    <td style="white-space: nowrap; text-align: right">0.138 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">81.91</td>
    <td style="white-space: nowrap; text-align: right">12.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;61.44%</td>
    <td style="white-space: nowrap; text-align: right">8.83 ms</td>
    <td style="white-space: nowrap; text-align: right">30.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">73.68</td>
    <td style="white-space: nowrap; text-align: right">13.57 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;76.64%</td>
    <td style="white-space: nowrap; text-align: right">21.00 ms</td>
    <td style="white-space: nowrap; text-align: right">27.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">72.63</td>
    <td style="white-space: nowrap; text-align: right">13.77 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;69.13%</td>
    <td style="white-space: nowrap; text-align: right">6.91 ms</td>
    <td style="white-space: nowrap; text-align: right">27.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">45.95</td>
    <td style="white-space: nowrap; text-align: right">21.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.72%</td>
    <td style="white-space: nowrap; text-align: right">16.31 ms</td>
    <td style="white-space: nowrap; text-align: right">37.68 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">20.12</td>
    <td style="white-space: nowrap; text-align: right">49.70 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.54%</td>
    <td style="white-space: nowrap; text-align: right">45.84 ms</td>
    <td style="white-space: nowrap; text-align: right">63.81 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.31</td>
    <td style="white-space: nowrap; text-align: right">107.46 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.29%</td>
    <td style="white-space: nowrap; text-align: right">113.25 ms</td>
    <td style="white-space: nowrap; text-align: right">118.75 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">5.43</td>
    <td style="white-space: nowrap; text-align: right">184.12 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.35%</td>
    <td style="white-space: nowrap; text-align: right">184.90 ms</td>
    <td style="white-space: nowrap; text-align: right">190.18 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.55</td>
    <td style="white-space: nowrap; text-align: right">1816.88 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.44%</td>
    <td style="white-space: nowrap; text-align: right">1819.16 ms</td>
    <td style="white-space: nowrap; text-align: right">1826.65 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.54</td>
    <td style="white-space: nowrap; text-align: right">1850.81 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.19%</td>
    <td style="white-space: nowrap; text-align: right">1858.41 ms</td>
    <td style="white-space: nowrap; text-align: right">1871.17 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.153</td>
    <td style="white-space: nowrap; text-align: right">6531.56 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.60%</td>
    <td style="white-space: nowrap; text-align: right">6531.56 ms</td>
    <td style="white-space: nowrap; text-align: right">6559.25 ms</td>
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
    <td style="white-space: nowrap;text-align: right">20558.38</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">9879.06</td>
    <td style="white-space: nowrap; text-align: right">2.08x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">81.91</td>
    <td style="white-space: nowrap; text-align: right">250.98x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">73.68</td>
    <td style="white-space: nowrap; text-align: right">279.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">72.63</td>
    <td style="white-space: nowrap; text-align: right">283.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">45.95</td>
    <td style="white-space: nowrap; text-align: right">447.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">20.12</td>
    <td style="white-space: nowrap; text-align: right">1021.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">9.31</td>
    <td style="white-space: nowrap; text-align: right">2209.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">5.43</td>
    <td style="white-space: nowrap; text-align: right">3785.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.55</td>
    <td style="white-space: nowrap; text-align: right">37352.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.54</td>
    <td style="white-space: nowrap; text-align: right">38049.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.153</td>
    <td style="white-space: nowrap; text-align: right">134278.24x</td>
  </tr>

</table>