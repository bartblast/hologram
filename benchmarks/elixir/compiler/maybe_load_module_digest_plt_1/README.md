Benchmark

Hologram.Compiler.maybe_load_module_digest_plt/1

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
    <td style="white-space: nowrap">no load</td>
    <td style="white-space: nowrap; text-align: right">146.39 K</td>
    <td style="white-space: nowrap; text-align: right">6.83 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;419.03%</td>
    <td style="white-space: nowrap; text-align: right">5.92 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">15.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">do load</td>
    <td style="white-space: nowrap; text-align: right">1.93 K</td>
    <td style="white-space: nowrap; text-align: right">517.34 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.87%</td>
    <td style="white-space: nowrap; text-align: right">505.29 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">727.47 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no load</td>
    <td style="white-space: nowrap;text-align: right">146.39 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">do load</td>
    <td style="white-space: nowrap; text-align: right">1.93 K</td>
    <td style="white-space: nowrap; text-align: right">75.73x</td>
  </tr>

</table>