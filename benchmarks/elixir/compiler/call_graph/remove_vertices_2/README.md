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
    <td style="white-space: nowrap; text-align: right">39.83 K</td>
    <td style="white-space: nowrap; text-align: right">25.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;120.06%</td>
    <td style="white-space: nowrap; text-align: right">22.73 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">194.09 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">35.25 K</td>
    <td style="white-space: nowrap; text-align: right">28.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;114.93%</td>
    <td style="white-space: nowrap; text-align: right">26.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">54.81 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">29.82 K</td>
    <td style="white-space: nowrap; text-align: right">33.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;24.33%</td>
    <td style="white-space: nowrap; text-align: right">33.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">67.55 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">19.52 K</td>
    <td style="white-space: nowrap; text-align: right">51.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.54%</td>
    <td style="white-space: nowrap; text-align: right">51.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">81.53 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.44 K</td>
    <td style="white-space: nowrap; text-align: right">95.80 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.33%</td>
    <td style="white-space: nowrap; text-align: right">94.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">123.90 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">308.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.35%</td>
    <td style="white-space: nowrap; text-align: right">294.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">400.79 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">39.83 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">35.25 K</td>
    <td style="white-space: nowrap; text-align: right">1.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">29.82 K</td>
    <td style="white-space: nowrap; text-align: right">1.34x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">19.52 K</td>
    <td style="white-space: nowrap; text-align: right">2.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.44 K</td>
    <td style="white-space: nowrap; text-align: right">3.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">12.29x</td>
  </tr>

</table>