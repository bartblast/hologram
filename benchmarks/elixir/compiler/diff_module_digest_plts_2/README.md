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
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.47 K</td>
    <td style="white-space: nowrap; text-align: right">223.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.52%</td>
    <td style="white-space: nowrap; text-align: right">220.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">271.37 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.70 K</td>
    <td style="white-space: nowrap; text-align: right">270.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.77%</td>
    <td style="white-space: nowrap; text-align: right">259.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">361.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.81 K</td>
    <td style="white-space: nowrap; text-align: right">355.93 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.98%</td>
    <td style="white-space: nowrap; text-align: right">346.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">445.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">545.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.10%</td>
    <td style="white-space: nowrap; text-align: right">541.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">619.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">545.84 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.57%</td>
    <td style="white-space: nowrap; text-align: right">540.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">619.41 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">548.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.67%</td>
    <td style="white-space: nowrap; text-align: right">545.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">605.82 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">562.73 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.93%</td>
    <td style="white-space: nowrap; text-align: right">559.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">618.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">565.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.66%</td>
    <td style="white-space: nowrap; text-align: right">564 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">617.05 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">567.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.82%</td>
    <td style="white-space: nowrap; text-align: right">566.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">627.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">569.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.58%</td>
    <td style="white-space: nowrap; text-align: right">566.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">624.20 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">571.47 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.88%</td>
    <td style="white-space: nowrap; text-align: right">566.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">640.84 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">591.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.32%</td>
    <td style="white-space: nowrap; text-align: right">574.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">744.90 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.47 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.70 K</td>
    <td style="white-space: nowrap; text-align: right">1.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.81 K</td>
    <td style="white-space: nowrap; text-align: right">1.59x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">2.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">2.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.45x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">2.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">2.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">2.64x</td>
  </tr>

</table>