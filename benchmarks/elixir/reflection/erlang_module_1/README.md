Benchmark

Hologram.Reflection.erlang_module?/1

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
    <td style="white-space: nowrap; text-align: right">173.21 M</td>
    <td style="white-space: nowrap; text-align: right">5.77 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4811.92%</td>
    <td style="white-space: nowrap; text-align: right">4.20 ns</td>
    <td style="white-space: nowrap; text-align: right">8.40 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">17.24 M</td>
    <td style="white-space: nowrap; text-align: right">58.02 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7452.04%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">16.27 M</td>
    <td style="white-space: nowrap; text-align: right">61.47 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7168.22%</td>
    <td style="white-space: nowrap; text-align: right">42 ns</td>
    <td style="white-space: nowrap; text-align: right">84 ns</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0801 M</td>
    <td style="white-space: nowrap; text-align: right">12476.72 ns</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.09%</td>
    <td style="white-space: nowrap; text-align: right">12250 ns</td>
    <td style="white-space: nowrap; text-align: right">17666 ns</td>
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
    <td style="white-space: nowrap;text-align: right">173.21 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">17.24 M</td>
    <td style="white-space: nowrap; text-align: right">10.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">16.27 M</td>
    <td style="white-space: nowrap; text-align: right">10.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0801 M</td>
    <td style="white-space: nowrap; text-align: right">2161.1x</td>
  </tr>

</table>