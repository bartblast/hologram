Benchmark

Hologram.Compiler.QueryExtractor.extract_module_queries/3

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
    <td style="white-space: nowrap; text-align: right">2836.72 K</td>
    <td style="white-space: nowrap; text-align: right">0.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2357.77%</td>
    <td style="white-space: nowrap; text-align: right">0.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">127.92 K</td>
    <td style="white-space: nowrap; text-align: right">7.82 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;171.30%</td>
    <td style="white-space: nowrap; text-align: right">7.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">103.48 K</td>
    <td style="white-space: nowrap; text-align: right">9.66 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;62.75%</td>
    <td style="white-space: nowrap; text-align: right">9.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">22.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">14.26 K</td>
    <td style="white-space: nowrap; text-align: right">70.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.37%</td>
    <td style="white-space: nowrap; text-align: right">71.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">87.04 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">2836.72 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">127.92 K</td>
    <td style="white-space: nowrap; text-align: right">22.18x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">103.48 K</td>
    <td style="white-space: nowrap; text-align: right">27.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">14.26 K</td>
    <td style="white-space: nowrap; text-align: right">198.91x</td>
  </tr>

</table>