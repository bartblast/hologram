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
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap; text-align: right">4.22 K</td>
    <td style="white-space: nowrap; text-align: right">236.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.09%</td>
    <td style="white-space: nowrap; text-align: right">231.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">300.88 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules added</td>
    <td style="white-space: nowrap; text-align: right">4.21 K</td>
    <td style="white-space: nowrap; text-align: right">237.70 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;13.81%</td>
    <td style="white-space: nowrap; text-align: right">233.46 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">296.96 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.08 K</td>
    <td style="white-space: nowrap; text-align: right">481.86 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.52%</td>
    <td style="white-space: nowrap; text-align: right">466.96 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">632.78 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.37 K</td>
    <td style="white-space: nowrap; text-align: right">728.48 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.99%</td>
    <td style="white-space: nowrap; text-align: right">705.58 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">956.09 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">751.91 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.04%</td>
    <td style="white-space: nowrap; text-align: right">723.50 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">1040.60 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">all modules removed</td>
    <td style="white-space: nowrap;text-align: right">4.22 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules added</td>
    <td style="white-space: nowrap; text-align: right">4.21 K</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1/3 added, 1/3 removed, 1/3 updated</td>
    <td style="white-space: nowrap; text-align: right">2.08 K</td>
    <td style="white-space: nowrap; text-align: right">2.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all modules updated</td>
    <td style="white-space: nowrap; text-align: right">1.37 K</td>
    <td style="white-space: nowrap; text-align: right">3.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">1.33 K</td>
    <td style="white-space: nowrap; text-align: right">3.17x</td>
  </tr>

</table>