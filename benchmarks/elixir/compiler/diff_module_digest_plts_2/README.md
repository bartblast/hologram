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
    <td style="white-space: nowrap; text-align: right">4.40 K</td>
    <td style="white-space: nowrap; text-align: right">227.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.13%</td>
    <td style="white-space: nowrap; text-align: right">223.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">286.99 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.41 K</td>
    <td style="white-space: nowrap; text-align: right">293.27 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.32%</td>
    <td style="white-space: nowrap; text-align: right">286.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">408.39 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.78 K</td>
    <td style="white-space: nowrap; text-align: right">360.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.40%</td>
    <td style="white-space: nowrap; text-align: right">359.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">455.62 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">548.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.12%</td>
    <td style="white-space: nowrap; text-align: right">543.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">614.68 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">570.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.18%</td>
    <td style="white-space: nowrap; text-align: right">565.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">676.39 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">570.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.12%</td>
    <td style="white-space: nowrap; text-align: right">565.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">647.78 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">579.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.28%</td>
    <td style="white-space: nowrap; text-align: right">576.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">673.40 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">584.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.42%</td>
    <td style="white-space: nowrap; text-align: right">583.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">651.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">586.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.35%</td>
    <td style="white-space: nowrap; text-align: right">579.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">683.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">586.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.45%</td>
    <td style="white-space: nowrap; text-align: right">566.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">725.36 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">590.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.35%</td>
    <td style="white-space: nowrap; text-align: right">588.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">658.07 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.67 K</td>
    <td style="white-space: nowrap; text-align: right">598.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.75%</td>
    <td style="white-space: nowrap; text-align: right">588.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">742.05 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.40 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.41 K</td>
    <td style="white-space: nowrap; text-align: right">1.29x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.78 K</td>
    <td style="white-space: nowrap; text-align: right">1.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.41x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">2.57x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.70 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">2.6x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.67 K</td>
    <td style="white-space: nowrap; text-align: right">2.63x</td>
  </tr>

</table>