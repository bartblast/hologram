Benchmark

Hologram.Compiler.CallGraph.list_modules_reaching/2

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
    <td style="white-space: nowrap">1 leaf module</td>
    <td style="white-space: nowrap; text-align: right">996.87</td>
    <td style="white-space: nowrap; text-align: right">1.00 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;157.26%</td>
    <td style="white-space: nowrap; text-align: right">0.90 ms</td>
    <td style="white-space: nowrap; text-align: right">1.77 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 core module</td>
    <td style="white-space: nowrap; text-align: right">858.02</td>
    <td style="white-space: nowrap; text-align: right">1.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.39%</td>
    <td style="white-space: nowrap; text-align: right">1.13 ms</td>
    <td style="white-space: nowrap; text-align: right">1.44 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 modules</td>
    <td style="white-space: nowrap; text-align: right">10.33</td>
    <td style="white-space: nowrap; text-align: right">96.76 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.12%</td>
    <td style="white-space: nowrap; text-align: right">95.59 ms</td>
    <td style="white-space: nowrap; text-align: right">123.52 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">1 leaf module</td>
    <td style="white-space: nowrap;text-align: right">996.87</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 core module</td>
    <td style="white-space: nowrap; text-align: right">858.02</td>
    <td style="white-space: nowrap; text-align: right">1.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 modules</td>
    <td style="white-space: nowrap; text-align: right">10.33</td>
    <td style="white-space: nowrap; text-align: right">96.46x</td>
  </tr>

</table>