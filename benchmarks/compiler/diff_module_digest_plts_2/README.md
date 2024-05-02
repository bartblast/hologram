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
    <td style="white-space: nowrap">1.16.1</td>
  </tr><tr>
    <th style="white-space: nowrap">Erlang Version</th>
    <td style="white-space: nowrap">26.2.2</td>
  </tr>
</table>

## Configuration

Benchmark suite executing with the following configuration:

<table style="width: 1%">
  <tr>
    <th style="width: 1%">:time</th>
    <td style="white-space: nowrap">1 s</td>
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
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.99 K</td>
    <td style="white-space: nowrap; text-align: right">250.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.28%</td>
    <td style="white-space: nowrap; text-align: right">252.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">272.49 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">3.92 K</td>
    <td style="white-space: nowrap; text-align: right">254.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.88%</td>
    <td style="white-space: nowrap; text-align: right">254.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">290.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">549.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.44%</td>
    <td style="white-space: nowrap; text-align: right">543.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">618.93 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.38 K</td>
    <td style="white-space: nowrap; text-align: right">726.81 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.53%</td>
    <td style="white-space: nowrap; text-align: right">721.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">789.16 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.36 K</td>
    <td style="white-space: nowrap; text-align: right">736.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.98%</td>
    <td style="white-space: nowrap; text-align: right">733.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">777.23 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">738.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.00%</td>
    <td style="white-space: nowrap; text-align: right">731.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">813.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">741.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.59%</td>
    <td style="white-space: nowrap; text-align: right">735.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">834.40 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">742.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.19%</td>
    <td style="white-space: nowrap; text-align: right">735.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">817.94 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.31 K</td>
    <td style="white-space: nowrap; text-align: right">766.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.33%</td>
    <td style="white-space: nowrap; text-align: right">761.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">879.65 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.30 K</td>
    <td style="white-space: nowrap; text-align: right">770.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.03%</td>
    <td style="white-space: nowrap; text-align: right">762.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">923.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.26 K</td>
    <td style="white-space: nowrap; text-align: right">792.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.82%</td>
    <td style="white-space: nowrap; text-align: right">783.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">931.28 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.17 K</td>
    <td style="white-space: nowrap; text-align: right">856.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.28%</td>
    <td style="white-space: nowrap; text-align: right">790 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">2489.40 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap;text-align: right">3.99 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">3.92 K</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.19x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">1.38 K</td>
    <td style="white-space: nowrap; text-align: right">2.9x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated</td>
    <td style="white-space: nowrap; text-align: right">1.36 K</td>
    <td style="white-space: nowrap; text-align: right">2.94x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">2.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">2.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.35 K</td>
    <td style="white-space: nowrap; text-align: right">2.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.31 K</td>
    <td style="white-space: nowrap; text-align: right">3.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.30 K</td>
    <td style="white-space: nowrap; text-align: right">3.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.26 K</td>
    <td style="white-space: nowrap; text-align: right">3.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">1.17 K</td>
    <td style="white-space: nowrap; text-align: right">3.42x</td>
  </tr>

</table>