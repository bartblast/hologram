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
    <td style="white-space: nowrap">1.18.2</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">27.2.4</td>
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
    <th style="text-align: right">Devitation</th>
    <th style="text-align: right">Median</th>
    <th style="text-align: right">99th&nbsp;%</th>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">1279.22 K</td>
    <td style="white-space: nowrap; text-align: right">0.78 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;62.41%</td>
    <td style="white-space: nowrap; text-align: right">0.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.62 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">875.91 K</td>
    <td style="white-space: nowrap; text-align: right">1.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;34.62%</td>
    <td style="white-space: nowrap; text-align: right">1.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">710.20 K</td>
    <td style="white-space: nowrap; text-align: right">1.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;36.67%</td>
    <td style="white-space: nowrap; text-align: right">1.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">574.71 K</td>
    <td style="white-space: nowrap; text-align: right">1.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;35.35%</td>
    <td style="white-space: nowrap; text-align: right">1.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">4.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">421.21 K</td>
    <td style="white-space: nowrap; text-align: right">2.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.59%</td>
    <td style="white-space: nowrap; text-align: right">2.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">5.38 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.0474 K</td>
    <td style="white-space: nowrap; text-align: right">21116.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.48%</td>
    <td style="white-space: nowrap; text-align: right">21092.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">21842.14 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">1279.22 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">875.91 K</td>
    <td style="white-space: nowrap; text-align: right">1.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">710.20 K</td>
    <td style="white-space: nowrap; text-align: right">1.8x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">574.71 K</td>
    <td style="white-space: nowrap; text-align: right">2.23x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">421.21 K</td>
    <td style="white-space: nowrap; text-align: right">3.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">0.0474 K</td>
    <td style="white-space: nowrap; text-align: right">27013.27x</td>
  </tr>

</table>