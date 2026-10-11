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
    <td style="white-space: nowrap; text-align: right">141.47 M</td>
    <td style="white-space: nowrap; text-align: right">0.00707 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4935.12%</td>
    <td style="white-space: nowrap; text-align: right">0.00830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.0167 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">2.12 M</td>
    <td style="white-space: nowrap; text-align: right">0.47 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1691.76%</td>
    <td style="white-space: nowrap; text-align: right">0.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0618 M</td>
    <td style="white-space: nowrap; text-align: right">16.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;41.73%</td>
    <td style="white-space: nowrap; text-align: right">15.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">0.00902 M</td>
    <td style="white-space: nowrap; text-align: right">110.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;38.11%</td>
    <td style="white-space: nowrap; text-align: right">106.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">181.93 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">141.47 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Erlang module</td>
    <td style="white-space: nowrap; text-align: right">2.12 M</td>
    <td style="white-space: nowrap; text-align: right">66.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is atom</td>
    <td style="white-space: nowrap; text-align: right">0.0618 M</td>
    <td style="white-space: nowrap; text-align: right">2288.98x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">is Elixir module</td>
    <td style="white-space: nowrap; text-align: right">0.00902 M</td>
    <td style="white-space: nowrap; text-align: right">15691.39x</td>
  </tr>

</table>