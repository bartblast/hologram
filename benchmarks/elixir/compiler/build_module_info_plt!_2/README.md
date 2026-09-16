Benchmark

Hologram.Compiler.build_module_info_plt!/2

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
    <td style="white-space: nowrap">previous dump, nothing changed (every entry reused)</td>
    <td style="white-space: nowrap; text-align: right">7.96</td>
    <td style="white-space: nowrap; text-align: right">125.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;26.76%</td>
    <td style="white-space: nowrap; text-align: right">114.85 ms</td>
    <td style="white-space: nowrap; text-align: right">327.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no previous dump (every beam read)</td>
    <td style="white-space: nowrap; text-align: right">5.33</td>
    <td style="white-space: nowrap; text-align: right">187.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;20.51%</td>
    <td style="white-space: nowrap; text-align: right">172.58 ms</td>
    <td style="white-space: nowrap; text-align: right">373.02 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">previous dump, nothing changed (every entry reused)</td>
    <td style="white-space: nowrap;text-align: right">7.96</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no previous dump (every beam read)</td>
    <td style="white-space: nowrap; text-align: right">5.33</td>
    <td style="white-space: nowrap; text-align: right">1.49x</td>
  </tr>

</table>