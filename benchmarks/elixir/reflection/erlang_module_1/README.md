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
    <td style="white-space: nowrap; text-align: right">24.12 M</td>
    <td style="white-space: nowrap; text-align: right">0.0415 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;160.32%</td>
    <td style="white-space: nowrap; text-align: right">0.0420 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0420 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">2.07 M</td>
    <td style="white-space: nowrap; text-align: right">0.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1831.06%</td>
    <td style="white-space: nowrap; text-align: right">0.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0614 M</td>
    <td style="white-space: nowrap; text-align: right">16.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;86.63%</td>
    <td style="white-space: nowrap; text-align: right">15.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">28.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">0.00835 M</td>
    <td style="white-space: nowrap; text-align: right">119.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.81%</td>
    <td style="white-space: nowrap; text-align: right">109.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">218.33 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">24.12 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">2.07 M</td>
    <td style="white-space: nowrap; text-align: right">11.66x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0614 M</td>
    <td style="white-space: nowrap; text-align: right">392.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">0.00835 M</td>
    <td style="white-space: nowrap; text-align: right">2888.43x</td>
  </tr>

</table>