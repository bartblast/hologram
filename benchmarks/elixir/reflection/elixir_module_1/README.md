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
    <td style="white-space: nowrap">is not atom</td>
    <td style="white-space: nowrap; text-align: right">28.30 M</td>
    <td style="white-space: nowrap; text-align: right">35.34 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5131.00%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">9.31 M</td>
    <td style="white-space: nowrap; text-align: right">107.42 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;42993.73%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">9.07 M</td>
    <td style="white-space: nowrap; text-align: right">110.27 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;43920.87%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">125 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">7.42 M</td>
    <td style="white-space: nowrap; text-align: right">134.85 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;37333.91%</td>
    <td style="white-space: nowrap; text-align: right">83 ns</td>
    <td style="white-space: nowrap; text-align: right">166 ns</td>
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
    <td style="white-space: nowrap;text-align: right">28.30 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">9.31 M</td>
    <td style="white-space: nowrap; text-align: right">3.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">9.07 M</td>
    <td style="white-space: nowrap; text-align: right">3.12x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">7.42 M</td>
    <td style="white-space: nowrap; text-align: right">3.82x</td>
  </tr>

</table>