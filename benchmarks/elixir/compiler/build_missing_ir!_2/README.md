Benchmark

Hologram.Compiler.build_missing_ir!/2

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
    <td style="white-space: nowrap">nothing missing</td>
    <td style="white-space: nowrap; text-align: right">7.90 K</td>
    <td style="white-space: nowrap; text-align: right">0.127 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.22%</td>
    <td style="white-space: nowrap; text-align: right">0.126 ms</td>
    <td style="white-space: nowrap; text-align: right">0.140 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all missing</td>
    <td style="white-space: nowrap; text-align: right">0.00156 K</td>
    <td style="white-space: nowrap; text-align: right">640.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.49%</td>
    <td style="white-space: nowrap; text-align: right">633.59 ms</td>
    <td style="white-space: nowrap; text-align: right">708.84 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">nothing missing</td>
    <td style="white-space: nowrap;text-align: right">7.90 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">all missing</td>
    <td style="white-space: nowrap; text-align: right">0.00156 K</td>
    <td style="white-space: nowrap; text-align: right">5054.65x</td>
  </tr>

</table>