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
    <td style="white-space: nowrap; text-align: right">4.71 K</td>
    <td style="white-space: nowrap; text-align: right">212.35 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.28%</td>
    <td style="white-space: nowrap; text-align: right">209.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">266.65 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.80 K</td>
    <td style="white-space: nowrap; text-align: right">263.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.16%</td>
    <td style="white-space: nowrap; text-align: right">244.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">360.68 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.79 K</td>
    <td style="white-space: nowrap; text-align: right">358.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.95%</td>
    <td style="white-space: nowrap; text-align: right">359.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">482.07 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.94 K</td>
    <td style="white-space: nowrap; text-align: right">514.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.35%</td>
    <td style="white-space: nowrap; text-align: right">515.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">584.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">531.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.27%</td>
    <td style="white-space: nowrap; text-align: right">521.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">687.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">539.89 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.85%</td>
    <td style="white-space: nowrap; text-align: right">541.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">653.26 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">541.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.89%</td>
    <td style="white-space: nowrap; text-align: right">540.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">671.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.84 K</td>
    <td style="white-space: nowrap; text-align: right">542.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.39%</td>
    <td style="white-space: nowrap; text-align: right">541.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">649.50 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">545.53 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.46%</td>
    <td style="white-space: nowrap; text-align: right">542.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">669.12 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">547.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.12%</td>
    <td style="white-space: nowrap; text-align: right">536.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">713.11 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">548.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.16%</td>
    <td style="white-space: nowrap; text-align: right">546.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">687.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">560.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.50%</td>
    <td style="white-space: nowrap; text-align: right">550.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">789.42 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.71 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.80 K</td>
    <td style="white-space: nowrap; text-align: right">1.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.79 K</td>
    <td style="white-space: nowrap; text-align: right">1.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.94 K</td>
    <td style="white-space: nowrap; text-align: right">2.42x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">2.54x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.85 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.84 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">2.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.83 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">2.64x</td>
  </tr>

</table>