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
    <td style="white-space: nowrap; text-align: right">87.94 K</td>
    <td style="white-space: nowrap; text-align: right">11.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.94%</td>
    <td style="white-space: nowrap; text-align: right">10.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27.39 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">49.28 K</td>
    <td style="white-space: nowrap; text-align: right">20.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;148.42%</td>
    <td style="white-space: nowrap; text-align: right">16.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">31.63 K</td>
    <td style="white-space: nowrap; text-align: right">31.62 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.84%</td>
    <td style="white-space: nowrap; text-align: right">29.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">61.66 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">16.39 K</td>
    <td style="white-space: nowrap; text-align: right">61.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.95%</td>
    <td style="white-space: nowrap; text-align: right">58.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">104.61 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.59 K</td>
    <td style="white-space: nowrap; text-align: right">94.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.98%</td>
    <td style="white-space: nowrap; text-align: right">91.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">145.47 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">4.11 K</td>
    <td style="white-space: nowrap; text-align: right">243.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.18%</td>
    <td style="white-space: nowrap; text-align: right">234.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">385.65 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">87.94 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">49.28 K</td>
    <td style="white-space: nowrap; text-align: right">1.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">31.63 K</td>
    <td style="white-space: nowrap; text-align: right">2.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">16.39 K</td>
    <td style="white-space: nowrap; text-align: right">5.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.59 K</td>
    <td style="white-space: nowrap; text-align: right">8.3x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">4.11 K</td>
    <td style="white-space: nowrap; text-align: right">21.4x</td>
  </tr>

</table>