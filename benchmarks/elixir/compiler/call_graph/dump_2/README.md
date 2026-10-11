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
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap; text-align: right">14.00</td>
    <td style="white-space: nowrap; text-align: right">71.44 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.50%</td>
    <td style="white-space: nowrap; text-align: right">69.94 ms</td>
    <td style="white-space: nowrap; text-align: right">105.19 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">13.82</td>
    <td style="white-space: nowrap; text-align: right">72.37 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.08%</td>
    <td style="white-space: nowrap; text-align: right">70.57 ms</td>
    <td style="white-space: nowrap; text-align: right">110.78 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">13.80</td>
    <td style="white-space: nowrap; text-align: right">72.47 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.80%</td>
    <td style="white-space: nowrap; text-align: right">69.42 ms</td>
    <td style="white-space: nowrap; text-align: right">156.60 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">dump dir doesn't exists</td>
    <td style="white-space: nowrap;text-align: right">14.00</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file exists</td>
    <td style="white-space: nowrap; text-align: right">13.82</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">dump dir exists, dump file doesn't exist</td>
    <td style="white-space: nowrap; text-align: right">13.80</td>
    <td style="white-space: nowrap; text-align: right">1.01x</td>
  </tr>

</table>