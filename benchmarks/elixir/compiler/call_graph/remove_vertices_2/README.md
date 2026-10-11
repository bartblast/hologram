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
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">856.51 K</td>
    <td style="white-space: nowrap; text-align: right">1.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;50.08%</td>
    <td style="white-space: nowrap; text-align: right">1.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.53 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">637.18 K</td>
    <td style="white-space: nowrap; text-align: right">1.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;53.10%</td>
    <td style="white-space: nowrap; text-align: right">1.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.30 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">518.57 K</td>
    <td style="white-space: nowrap; text-align: right">1.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;72.49%</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.32 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">429.08 K</td>
    <td style="white-space: nowrap; text-align: right">2.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;50.50%</td>
    <td style="white-space: nowrap; text-align: right">2.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">380.17 K</td>
    <td style="white-space: nowrap; text-align: right">2.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;39.17%</td>
    <td style="white-space: nowrap; text-align: right">2.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.65 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">337.34 K</td>
    <td style="white-space: nowrap; text-align: right">2.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.57%</td>
    <td style="white-space: nowrap; text-align: right">2.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.67 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap;text-align: right">856.51 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">637.18 K</td>
    <td style="white-space: nowrap; text-align: right">1.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">518.57 K</td>
    <td style="white-space: nowrap; text-align: right">1.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">429.08 K</td>
    <td style="white-space: nowrap; text-align: right">2.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">380.17 K</td>
    <td style="white-space: nowrap; text-align: right">2.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">337.34 K</td>
    <td style="white-space: nowrap; text-align: right">2.54x</td>
  </tr>

</table>