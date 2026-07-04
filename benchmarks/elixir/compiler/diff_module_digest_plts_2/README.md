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
    <td style="white-space: nowrap; text-align: right">223.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.25%</td>
    <td style="white-space: nowrap; text-align: right">221.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">255.12 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.70 K</td>
    <td style="white-space: nowrap; text-align: right">270.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.89%</td>
    <td style="white-space: nowrap; text-align: right">259.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">364.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.74 K</td>
    <td style="white-space: nowrap; text-align: right">364.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.52%</td>
    <td style="white-space: nowrap; text-align: right">363.37 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">461.17 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">548.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.62%</td>
    <td style="white-space: nowrap; text-align: right">543.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">628.12 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">549.45 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.71%</td>
    <td style="white-space: nowrap; text-align: right">542.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">621.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">558.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.50%</td>
    <td style="white-space: nowrap; text-align: right">559.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">644.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">564.61 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.96%</td>
    <td style="white-space: nowrap; text-align: right">563.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">623.16 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">565.23 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.85%</td>
    <td style="white-space: nowrap; text-align: right">564.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">623.05 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">566.57 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.24%</td>
    <td style="white-space: nowrap; text-align: right">565.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">635.20 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">566.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.94%</td>
    <td style="white-space: nowrap; text-align: right">565.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">626.86 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">571.36 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.43%</td>
    <td style="white-space: nowrap; text-align: right">564.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">657.75 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">578.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.18%</td>
    <td style="white-space: nowrap; text-align: right">564.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">712.67 &micro;s</td>
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
    <td style="white-space: nowrap; text-align: right">2.74 K</td>
    <td style="white-space: nowrap; text-align: right">1.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.45x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.82 K</td>
    <td style="white-space: nowrap; text-align: right">2.46x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.79 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">2.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">2.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.77 K</td>
    <td style="white-space: nowrap; text-align: right">2.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.53x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">2.59x</td>
  </tr>

</table>