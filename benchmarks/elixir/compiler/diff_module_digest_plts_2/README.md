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
    <td style="white-space: nowrap; text-align: right">3.38 K</td>
    <td style="white-space: nowrap; text-align: right">295.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.64%</td>
    <td style="white-space: nowrap; text-align: right">292.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">336.11 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">308.77 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.43%</td>
    <td style="white-space: nowrap; text-align: right">305.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">354.89 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.64 K</td>
    <td style="white-space: nowrap; text-align: right">610.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.58%</td>
    <td style="white-space: nowrap; text-align: right">605.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">764 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.11 K</td>
    <td style="white-space: nowrap; text-align: right">900.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.24%</td>
    <td style="white-space: nowrap; text-align: right">892.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1029.95 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.09 K</td>
    <td style="white-space: nowrap; text-align: right">918.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.97%</td>
    <td style="white-space: nowrap; text-align: right">902.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1108.57 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">932.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.34%</td>
    <td style="white-space: nowrap; text-align: right">928.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1090.29 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">936.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.58%</td>
    <td style="white-space: nowrap; text-align: right">916.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1198.47 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.05 K</td>
    <td style="white-space: nowrap; text-align: right">950.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.42%</td>
    <td style="white-space: nowrap; text-align: right">931.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1094.21 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.04 K</td>
    <td style="white-space: nowrap; text-align: right">959.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.52%</td>
    <td style="white-space: nowrap; text-align: right">948.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1117.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.02 K</td>
    <td style="white-space: nowrap; text-align: right">975.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.32%</td>
    <td style="white-space: nowrap; text-align: right">963.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1122.91 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.01 K</td>
    <td style="white-space: nowrap; text-align: right">990.74 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.91%</td>
    <td style="white-space: nowrap; text-align: right">982.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1144.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">0.99 K</td>
    <td style="white-space: nowrap; text-align: right">1009.95 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.38%</td>
    <td style="white-space: nowrap; text-align: right">1006.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1153.59 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">3.38 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.24 K</td>
    <td style="white-space: nowrap; text-align: right">1.04x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.64 K</td>
    <td style="white-space: nowrap; text-align: right">2.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.11 K</td>
    <td style="white-space: nowrap; text-align: right">3.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.09 K</td>
    <td style="white-space: nowrap; text-align: right">3.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">3.15x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.07 K</td>
    <td style="white-space: nowrap; text-align: right">3.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.05 K</td>
    <td style="white-space: nowrap; text-align: right">3.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.04 K</td>
    <td style="white-space: nowrap; text-align: right">3.25x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.02 K</td>
    <td style="white-space: nowrap; text-align: right">3.3x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.01 K</td>
    <td style="white-space: nowrap; text-align: right">3.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">0.99 K</td>
    <td style="white-space: nowrap; text-align: right">3.42x</td>
  </tr>

</table>