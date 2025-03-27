Benchmark

Hologram.Compiler.maybe_install_js_deps/2

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
    <td style="white-space: nowrap">no install</td>
    <td style="white-space: nowrap; text-align: right">11.38 K</td>
    <td style="white-space: nowrap; text-align: right">0.00009 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;66.96%</td>
    <td style="white-space: nowrap; text-align: right">0.00009 s</td>
    <td style="white-space: nowrap; text-align: right">0.00018 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">do install</td>
    <td style="white-space: nowrap; text-align: right">0.00008 K</td>
    <td style="white-space: nowrap; text-align: right">13.26 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;73.88%</td>
    <td style="white-space: nowrap; text-align: right">9.83 s</td>
    <td style="white-space: nowrap; text-align: right">33.10 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no install</td>
    <td style="white-space: nowrap;text-align: right">11.38 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">do install</td>
    <td style="white-space: nowrap; text-align: right">0.00008 K</td>
    <td style="white-space: nowrap; text-align: right">150895.75x</td>
  </tr>

</table>