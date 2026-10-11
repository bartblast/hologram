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
    <td style="white-space: nowrap; text-align: right">2911.06 K</td>
    <td style="white-space: nowrap; text-align: right">0.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1738.31%</td>
    <td style="white-space: nowrap; text-align: right">0.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">6.98 K</td>
    <td style="white-space: nowrap; text-align: right">143.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;48.39%</td>
    <td style="white-space: nowrap; text-align: right">142 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">183.91 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">6.92 K</td>
    <td style="white-space: nowrap; text-align: right">144.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.83%</td>
    <td style="white-space: nowrap; text-align: right">143.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">181.89 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">4.72 K</td>
    <td style="white-space: nowrap; text-align: right">211.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.52%</td>
    <td style="white-space: nowrap; text-align: right">209.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">245.29 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">2911.06 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">6.98 K</td>
    <td style="white-space: nowrap; text-align: right">416.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">6.92 K</td>
    <td style="white-space: nowrap; text-align: right">420.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">4.72 K</td>
    <td style="white-space: nowrap; text-align: right">616.65x</td>
  </tr>

</table>