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
    <td style="white-space: nowrap; text-align: right">4.68 K</td>
    <td style="white-space: nowrap; text-align: right">213.60 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.09%</td>
    <td style="white-space: nowrap; text-align: right">213.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">251.36 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.78 K</td>
    <td style="white-space: nowrap; text-align: right">264.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.66%</td>
    <td style="white-space: nowrap; text-align: right">249.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">362.52 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.90 K</td>
    <td style="white-space: nowrap; text-align: right">345.33 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.36%</td>
    <td style="white-space: nowrap; text-align: right">351.21 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">436.09 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">532.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.19%</td>
    <td style="white-space: nowrap; text-align: right">528.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">611.64 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">533.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.01%</td>
    <td style="white-space: nowrap; text-align: right">531.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">596.99 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">551.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.58%</td>
    <td style="white-space: nowrap; text-align: right">551.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">618.73 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.80 K</td>
    <td style="white-space: nowrap; text-align: right">554.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.18%</td>
    <td style="white-space: nowrap; text-align: right">552.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">679.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">561.44 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.04%</td>
    <td style="white-space: nowrap; text-align: right">549.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">677.25 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">569.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.48%</td>
    <td style="white-space: nowrap; text-align: right">563.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">690.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">572.24 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;40.46%</td>
    <td style="white-space: nowrap; text-align: right">551.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">662.28 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">577.56 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.44%</td>
    <td style="white-space: nowrap; text-align: right">553.25 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">714.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">586.26 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.51%</td>
    <td style="white-space: nowrap; text-align: right">566.17 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">702.00 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.68 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">3.78 K</td>
    <td style="white-space: nowrap; text-align: right">1.24x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">2.90 K</td>
    <td style="white-space: nowrap; text-align: right">1.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">2.49x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">1.88 K</td>
    <td style="white-space: nowrap; text-align: right">2.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">1.81 K</td>
    <td style="white-space: nowrap; text-align: right">2.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">1.80 K</td>
    <td style="white-space: nowrap; text-align: right">2.59x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited</td>
    <td style="white-space: nowrap; text-align: right">1.78 K</td>
    <td style="white-space: nowrap; text-align: right">2.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">1.76 K</td>
    <td style="white-space: nowrap; text-align: right">2.67x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">1.75 K</td>
    <td style="white-space: nowrap; text-align: right">2.68x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed</td>
    <td style="white-space: nowrap; text-align: right">1.73 K</td>
    <td style="white-space: nowrap; text-align: right">2.7x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added</td>
    <td style="white-space: nowrap; text-align: right">1.71 K</td>
    <td style="white-space: nowrap; text-align: right">2.74x</td>
  </tr>

</table>