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
    <td style="white-space: nowrap; text-align: right">4.69 K</td>
    <td style="white-space: nowrap; text-align: right">213.22 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.95%</td>
    <td style="white-space: nowrap; text-align: right">213.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">248.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.69 K</td>
    <td style="white-space: nowrap; text-align: right">271.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.52%</td>
    <td style="white-space: nowrap; text-align: right">246.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">385.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.85 K</td>
    <td style="white-space: nowrap; text-align: right">351.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.11%</td>
    <td style="white-space: nowrap; text-align: right">354.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">434.82 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">533.02 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.34%</td>
    <td style="white-space: nowrap; text-align: right">529.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">598.99 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">549.51 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.05%</td>
    <td style="white-space: nowrap; text-align: right">545.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">636.76 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">552.20 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.74%</td>
    <td style="white-space: nowrap; text-align: right">550.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">673.84 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">553.59 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.21%</td>
    <td style="white-space: nowrap; text-align: right">553.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">624.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">560.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.57%</td>
    <td style="white-space: nowrap; text-align: right">554.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">652.82 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">565.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.01%</td>
    <td style="white-space: nowrap; text-align: right">563.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">636.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">572.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.56%</td>
    <td style="white-space: nowrap; text-align: right">573.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">660.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">573.14 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.82%</td>
    <td style="white-space: nowrap; text-align: right">572.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">648.94 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">593.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.29%</td>
    <td style="white-space: nowrap; text-align: right">591.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">684.86 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.69 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.69 K</td>
    <td style="white-space: nowrap; text-align: right">1.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.85 K</td>
    <td style="white-space: nowrap; text-align: right">1.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">2.59x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">2.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">2.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">2.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.68x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">2.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">2.78x</td>
  </tr>

</table>