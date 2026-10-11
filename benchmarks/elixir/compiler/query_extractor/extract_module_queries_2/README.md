Benchmark

Hologram.Compiler.QueryExtractor.extract_module_queries/2

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
    <td style="white-space: nowrap">no parameterized captures</td>
    <td style="white-space: nowrap; text-align: right">2909.91 K</td>
    <td style="white-space: nowrap; text-align: right">0.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1508.69%</td>
    <td style="white-space: nowrap; text-align: right">0.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">6.57 K</td>
    <td style="white-space: nowrap; text-align: right">152.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.26%</td>
    <td style="white-space: nowrap; text-align: right">151.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">192.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">6.46 K</td>
    <td style="white-space: nowrap; text-align: right">154.90 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;33.56%</td>
    <td style="white-space: nowrap; text-align: right">153.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">211.10 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">4.62 K</td>
    <td style="white-space: nowrap; text-align: right">216.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.06%</td>
    <td style="white-space: nowrap; text-align: right">214.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">246.13 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no parameterized captures</td>
    <td style="white-space: nowrap;text-align: right">2909.91 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">6.57 K</td>
    <td style="white-space: nowrap; text-align: right">442.89x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">6.46 K</td>
    <td style="white-space: nowrap; text-align: right">450.73x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">4.62 K</td>
    <td style="white-space: nowrap; text-align: right">630.08x</td>
  </tr>

</table>