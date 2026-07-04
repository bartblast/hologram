Benchmark

Hologram.Reflection.elixir_module?/1

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
    <td style="white-space: nowrap">is not atom</td>
    <td style="white-space: nowrap; text-align: right">29.81 M</td>
    <td style="white-space: nowrap; text-align: right">33.55 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;57.90%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">12.35 M</td>
    <td style="white-space: nowrap; text-align: right">80.95 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9719.36%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">11.27 M</td>
    <td style="white-space: nowrap; text-align: right">88.70 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9103.90%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">167 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">9.38 M</td>
    <td style="white-space: nowrap; text-align: right">106.62 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6272.66%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">is not atom</td>
    <td style="white-space: nowrap;text-align: right">29.81 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">12.35 M</td>
    <td style="white-space: nowrap; text-align: right">2.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">11.27 M</td>
    <td style="white-space: nowrap; text-align: right">2.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">9.38 M</td>
    <td style="white-space: nowrap; text-align: right">3.18x</td>
  </tr>

</table>