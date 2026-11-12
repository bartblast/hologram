Benchmark

Hologram.Compiler.QueryExtractor.extract_derived_queries/3

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
    <td style="white-space: nowrap">no derived fields</td>
    <td style="white-space: nowrap; text-align: right">2824.92 K</td>
    <td style="white-space: nowrap; text-align: right">0.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4334.57%</td>
    <td style="white-space: nowrap; text-align: right">0.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field naming its entity</td>
    <td style="white-space: nowrap; text-align: right">58.26 K</td>
    <td style="white-space: nowrap; text-align: right">17.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;292.71%</td>
    <td style="white-space: nowrap; text-align: right">14.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">81.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">57.26 K</td>
    <td style="white-space: nowrap; text-align: right">17.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;91.88%</td>
    <td style="white-space: nowrap; text-align: right">15.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">47.07 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">13.03 K</td>
    <td style="white-space: nowrap; text-align: right">76.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;231.43%</td>
    <td style="white-space: nowrap; text-align: right">71.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">159.21 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no derived fields</td>
    <td style="white-space: nowrap;text-align: right">2824.92 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field naming its entity</td>
    <td style="white-space: nowrap; text-align: right">58.26 K</td>
    <td style="white-space: nowrap; text-align: right">48.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">57.26 K</td>
    <td style="white-space: nowrap; text-align: right">49.33x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">field whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">13.03 K</td>
    <td style="white-space: nowrap; text-align: right">216.8x</td>
  </tr>

</table>