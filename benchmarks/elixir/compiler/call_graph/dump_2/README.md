Benchmark

Hologram.Compiler.CallGraph.dump/2

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
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">25.06</td>
    <td style="white-space: nowrap; text-align: right">39.91 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.15%</td>
    <td style="white-space: nowrap; text-align: right">39.23 ms</td>
    <td style="white-space: nowrap; text-align: right">57.67 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">25.01</td>
    <td style="white-space: nowrap; text-align: right">39.99 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.86%</td>
    <td style="white-space: nowrap; text-align: right">39.64 ms</td>
    <td style="white-space: nowrap; text-align: right">54.92 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">24.49</td>
    <td style="white-space: nowrap; text-align: right">40.83 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.17%</td>
    <td style="white-space: nowrap; text-align: right">40.28 ms</td>
    <td style="white-space: nowrap; text-align: right">55.81 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap;text-align: right">25.06</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">25.01</td>
    <td style="white-space: nowrap; text-align: right">1.0x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">24.49</td>
    <td style="white-space: nowrap; text-align: right">1.02x</td>
  </tr>

</table>