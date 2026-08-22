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
    <td style="white-space: nowrap; text-align: right">9183.85 K</td>
    <td style="white-space: nowrap; text-align: right">0.109 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7780.67%</td>
    <td style="white-space: nowrap; text-align: right">0.0830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.166 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">2.02 K</td>
    <td style="white-space: nowrap; text-align: right">493.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.07%</td>
    <td style="white-space: nowrap; text-align: right">495.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">708.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">626.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;25.46%</td>
    <td style="white-space: nowrap; text-align: right">625.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">892.77 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">1.41 K</td>
    <td style="white-space: nowrap; text-align: right">707.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.69%</td>
    <td style="white-space: nowrap; text-align: right">707.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">986.50 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">9183.85 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture naming its entity</td>
    <td style="white-space: nowrap; text-align: right">2.02 K</td>
    <td style="white-space: nowrap; text-align: right">4536.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 1 candidate</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">5749.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">capture whose entity is an argument, 21 candidates</td>
    <td style="white-space: nowrap; text-align: right">1.41 K</td>
    <td style="white-space: nowrap; text-align: right">6498.23x</td>
  </tr>

</table>