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
    <td style="white-space: nowrap; text-align: right">72.56 K</td>
    <td style="white-space: nowrap; text-align: right">13.78 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;93.57%</td>
    <td style="white-space: nowrap; text-align: right">12.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">31.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">48.69 K</td>
    <td style="white-space: nowrap; text-align: right">20.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;131.00%</td>
    <td style="white-space: nowrap; text-align: right">18.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">32.23 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">34.40 K</td>
    <td style="white-space: nowrap; text-align: right">29.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;108.64%</td>
    <td style="white-space: nowrap; text-align: right">25.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">43.31 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">12.57 K</td>
    <td style="white-space: nowrap; text-align: right">79.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;30.17%</td>
    <td style="white-space: nowrap; text-align: right">76.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">109.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">6.56 K</td>
    <td style="white-space: nowrap; text-align: right">152.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.27%</td>
    <td style="white-space: nowrap; text-align: right">147.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">208.98 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.02 K</td>
    <td style="white-space: nowrap; text-align: right">330.80 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.47%</td>
    <td style="white-space: nowrap; text-align: right">323.02 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">439.68 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">72.56 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">48.69 K</td>
    <td style="white-space: nowrap; text-align: right">1.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">34.40 K</td>
    <td style="white-space: nowrap; text-align: right">2.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">12.57 K</td>
    <td style="white-space: nowrap; text-align: right">5.77x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">6.56 K</td>
    <td style="white-space: nowrap; text-align: right">11.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.02 K</td>
    <td style="white-space: nowrap; text-align: right">24.0x</td>
  </tr>

</table>