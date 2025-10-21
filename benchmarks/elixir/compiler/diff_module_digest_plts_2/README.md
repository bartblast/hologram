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
    <td style="white-space: nowrap; text-align: right">4.40 K</td>
    <td style="white-space: nowrap; text-align: right">227.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.41%</td>
    <td style="white-space: nowrap; text-align: right">227.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">274.48 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.55 K</td>
    <td style="white-space: nowrap; text-align: right">281.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.90%</td>
    <td style="white-space: nowrap; text-align: right">267.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">392.90 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.66 K</td>
    <td style="white-space: nowrap; text-align: right">376.13 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.06%</td>
    <td style="white-space: nowrap; text-align: right">379.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">480.31 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">552.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.20%</td>
    <td style="white-space: nowrap; text-align: right">547.69 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">636.12 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">553.09 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.30%</td>
    <td style="white-space: nowrap; text-align: right">547.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">645.05 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">566.94 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.77%</td>
    <td style="white-space: nowrap; text-align: right">564.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">664.79 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">567.10 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.20%</td>
    <td style="white-space: nowrap; text-align: right">563.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">652.24 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">567.97 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.20%</td>
    <td style="white-space: nowrap; text-align: right">564.71 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">650.63 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">568.16 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.42%</td>
    <td style="white-space: nowrap; text-align: right">563.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">659.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">571.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.16%</td>
    <td style="white-space: nowrap; text-align: right">567.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">655.01 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">573.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.52%</td>
    <td style="white-space: nowrap; text-align: right">567.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">668.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">590.07 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.81%</td>
    <td style="white-space: nowrap; text-align: right">586.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">748.11 &micro;s</td>
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
    <td style="white-space: nowrap; text-align: right">3.55 K</td>
    <td style="white-space: nowrap; text-align: right">1.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.66 K</td>
    <td style="white-space: nowrap; text-align: right">1.65x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">2.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">2.43x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.74 K</td>
    <td style="white-space: nowrap; text-align: right">2.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.69 K</td>
    <td style="white-space: nowrap; text-align: right">2.59x</td>
  </tr>

</table>