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
    <td style="white-space: nowrap; text-align: right">4.28 K</td>
    <td style="white-space: nowrap; text-align: right">233.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.84%</td>
    <td style="white-space: nowrap; text-align: right">229.88 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">270.54 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.25 K</td>
    <td style="white-space: nowrap; text-align: right">235.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.45%</td>
    <td style="white-space: nowrap; text-align: right">230.79 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">297.58 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.18 K</td>
    <td style="white-space: nowrap; text-align: right">459.12 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.68%</td>
    <td style="white-space: nowrap; text-align: right">448 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">547.08 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.45 K</td>
    <td style="white-space: nowrap; text-align: right">687.85 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.84%</td>
    <td style="white-space: nowrap; text-align: right">688.41 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">808.99 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.41 K</td>
    <td style="white-space: nowrap; text-align: right">708.00 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.84%</td>
    <td style="white-space: nowrap; text-align: right">692.03 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">849.45 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">4.28 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.25 K</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.18 K</td>
    <td style="white-space: nowrap; text-align: right">1.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.45 K</td>
    <td style="white-space: nowrap; text-align: right">2.94x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.41 K</td>
    <td style="white-space: nowrap; text-align: right">3.03x</td>
  </tr>

</table>