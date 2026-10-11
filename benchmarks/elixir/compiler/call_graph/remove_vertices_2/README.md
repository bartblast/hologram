Benchmark

Hologram.Compiler.CallGraph.remove_vertices/2

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
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">1223.41 K</td>
    <td style="white-space: nowrap; text-align: right">0.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.44%</td>
    <td style="white-space: nowrap; text-align: right">0.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.80 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">1021.14 K</td>
    <td style="white-space: nowrap; text-align: right">0.98 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;37.39%</td>
    <td style="white-space: nowrap; text-align: right">0.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.97 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">951.39 K</td>
    <td style="white-space: nowrap; text-align: right">1.05 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.82%</td>
    <td style="white-space: nowrap; text-align: right">1 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.69 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">818.56 K</td>
    <td style="white-space: nowrap; text-align: right">1.22 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.47%</td>
    <td style="white-space: nowrap; text-align: right">1.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">645.65 K</td>
    <td style="white-space: nowrap; text-align: right">1.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.91%</td>
    <td style="white-space: nowrap; text-align: right">1.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.65 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">377.95 K</td>
    <td style="white-space: nowrap; text-align: right">2.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.06%</td>
    <td style="white-space: nowrap; text-align: right">2.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.96 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap;text-align: right">1223.41 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">1021.14 K</td>
    <td style="white-space: nowrap; text-align: right">1.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">951.39 K</td>
    <td style="white-space: nowrap; text-align: right">1.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">818.56 K</td>
    <td style="white-space: nowrap; text-align: right">1.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">645.65 K</td>
    <td style="white-space: nowrap; text-align: right">1.89x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">377.95 K</td>
    <td style="white-space: nowrap; text-align: right">3.24x</td>
  </tr>

</table>