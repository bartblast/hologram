Benchmark

Hologram.Compiler.diff_module_digest_plts/2

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
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">3.39 K</td>
    <td style="white-space: nowrap; text-align: right">295.22 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.76%</td>
    <td style="white-space: nowrap; text-align: right">287.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">370.74 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">308.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.14%</td>
    <td style="white-space: nowrap; text-align: right">299.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">406.19 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.61 K</td>
    <td style="white-space: nowrap; text-align: right">620.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.63%</td>
    <td style="white-space: nowrap; text-align: right">616.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">775.16 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">911.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.44%</td>
    <td style="white-space: nowrap; text-align: right">909.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1024.64 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">911.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.51%</td>
    <td style="white-space: nowrap; text-align: right">900.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1034.11 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">912.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.36%</td>
    <td style="white-space: nowrap; text-align: right">903.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1041.03 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">913.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.76%</td>
    <td style="white-space: nowrap; text-align: right">897.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1129.94 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">924.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.09%</td>
    <td style="white-space: nowrap; text-align: right">909.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1098.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">928.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.70%</td>
    <td style="white-space: nowrap; text-align: right">908.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1171.98 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">935.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.28%</td>
    <td style="white-space: nowrap; text-align: right">921.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1094.55 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">938.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.81%</td>
    <td style="white-space: nowrap; text-align: right">926.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1068.74 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.06 K</td>
    <td style="white-space: nowrap; text-align: right">944.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.80%</td>
    <td style="white-space: nowrap; text-align: right">933.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1069.25 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap;text-align: right">3.39 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.61 K</td>
    <td style="white-space: nowrap; text-align: right">2.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">3.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">3.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">3.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.10 K</td>
    <td style="white-space: nowrap; text-align: right">3.09x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">3.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.08 K</td>
    <td style="white-space: nowrap; text-align: right">3.14x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">3.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">3.18x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.06 K</td>
    <td style="white-space: nowrap; text-align: right">3.2x</td>
  </tr>

</table>