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
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">1056.03 K</td>
    <td style="white-space: nowrap; text-align: right">0.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.84%</td>
    <td style="white-space: nowrap; text-align: right">0.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.69 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">996.10 K</td>
    <td style="white-space: nowrap; text-align: right">1.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;35.92%</td>
    <td style="white-space: nowrap; text-align: right">0.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">959.60 K</td>
    <td style="white-space: nowrap; text-align: right">1.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;30.42%</td>
    <td style="white-space: nowrap; text-align: right">1 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">831.12 K</td>
    <td style="white-space: nowrap; text-align: right">1.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;61.48%</td>
    <td style="white-space: nowrap; text-align: right">0.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">649.05 K</td>
    <td style="white-space: nowrap; text-align: right">1.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.82%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">3.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">425.63 K</td>
    <td style="white-space: nowrap; text-align: right">2.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.05%</td>
    <td style="white-space: nowrap; text-align: right">2.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.23 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap;text-align: right">1056.03 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">996.10 K</td>
    <td style="white-space: nowrap; text-align: right">1.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">959.60 K</td>
    <td style="white-space: nowrap; text-align: right">1.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">831.12 K</td>
    <td style="white-space: nowrap; text-align: right">1.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">649.05 K</td>
    <td style="white-space: nowrap; text-align: right">1.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">425.63 K</td>
    <td style="white-space: nowrap; text-align: right">2.48x</td>
  </tr>

</table>