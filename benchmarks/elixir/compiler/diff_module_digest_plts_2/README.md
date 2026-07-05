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
    <td style="white-space: nowrap; text-align: right">4.38 K</td>
    <td style="white-space: nowrap; text-align: right">228.42 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.93%</td>
    <td style="white-space: nowrap; text-align: right">226.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">260.13 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.45 K</td>
    <td style="white-space: nowrap; text-align: right">289.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;39.02%</td>
    <td style="white-space: nowrap; text-align: right">268.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">443.12 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.65 K</td>
    <td style="white-space: nowrap; text-align: right">377.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.42%</td>
    <td style="white-space: nowrap; text-align: right">373.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">488.15 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">584.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.88%</td>
    <td style="white-space: nowrap; text-align: right">579.66 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">670.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">588.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.17%</td>
    <td style="white-space: nowrap; text-align: right">585.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">649.35 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">593.18 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.06%</td>
    <td style="white-space: nowrap; text-align: right">590.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">680.46 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.67 K</td>
    <td style="white-space: nowrap; text-align: right">597.66 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.51%</td>
    <td style="white-space: nowrap; text-align: right">582.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">758.03 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.66 K</td>
    <td style="white-space: nowrap; text-align: right">602.28 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.15%</td>
    <td style="white-space: nowrap; text-align: right">585.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">725.35 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.62 K</td>
    <td style="white-space: nowrap; text-align: right">618.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.12%</td>
    <td style="white-space: nowrap; text-align: right">611.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">794.26 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.62 K</td>
    <td style="white-space: nowrap; text-align: right">618.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.44%</td>
    <td style="white-space: nowrap; text-align: right">609.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">751.41 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">625.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.66%</td>
    <td style="white-space: nowrap; text-align: right">615.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">743.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.59 K</td>
    <td style="white-space: nowrap; text-align: right">627.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.44%</td>
    <td style="white-space: nowrap; text-align: right">618.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">780.64 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.38 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.45 K</td>
    <td style="white-space: nowrap; text-align: right">1.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.65 K</td>
    <td style="white-space: nowrap; text-align: right">1.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">2.56x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">2.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.67 K</td>
    <td style="white-space: nowrap; text-align: right">2.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.66 K</td>
    <td style="white-space: nowrap; text-align: right">2.64x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.62 K</td>
    <td style="white-space: nowrap; text-align: right">2.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.62 K</td>
    <td style="white-space: nowrap; text-align: right">2.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.60 K</td>
    <td style="white-space: nowrap; text-align: right">2.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.59 K</td>
    <td style="white-space: nowrap; text-align: right">2.75x</td>
  </tr>

</table>