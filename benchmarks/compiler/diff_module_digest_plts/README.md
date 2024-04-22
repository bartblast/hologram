Benchmark

diff_module_digest_plts/2

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
    <td style="white-space: nowrap">1 min</td>
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
    <td style="white-space: nowrap">all modules added</td>
    <td style="white-space: nowrap; text-align: right">4.25 K</td>
    <td style="white-space: nowrap; text-align: right">235.55 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.91%</td>
    <td style="white-space: nowrap; text-align: right">232.04 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">277.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.22 K</td>
    <td style="white-space: nowrap; text-align: right">236.73 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.87%</td>
    <td style="white-space: nowrap; text-align: right">233.67 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">281.71 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.15 K</td>
    <td style="white-space: nowrap; text-align: right">465.01 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.75%</td>
    <td style="white-space: nowrap; text-align: right">455.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">563.04 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">752.52 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;42.13%</td>
    <td style="white-space: nowrap; text-align: right">714.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1062.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.27 K</td>
    <td style="white-space: nowrap; text-align: right">787.31 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;68.94%</td>
    <td style="white-space: nowrap; text-align: right">737.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1159.55 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">all modules added</td>
    <td style="white-space: nowrap;text-align: right">4.25 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.22 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.15 K</td>
    <td style="white-space: nowrap; text-align: right">1.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">3.19x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.27 K</td>
    <td style="white-space: nowrap; text-align: right">3.34x</td>
  </tr>

</table>