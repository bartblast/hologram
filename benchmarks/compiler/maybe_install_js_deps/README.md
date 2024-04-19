Benchmark

maybe_install_js_deps/2

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
    <td style="white-space: nowrap">with cache</td>
    <td style="white-space: nowrap; text-align: right">4.68 K</td>
    <td style="white-space: nowrap; text-align: right">0.00021 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.02%</td>
    <td style="white-space: nowrap; text-align: right">0.00021 s</td>
    <td style="white-space: nowrap; text-align: right">0.00039 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">without cache</td>
    <td style="white-space: nowrap; text-align: right">0.00007 K</td>
    <td style="white-space: nowrap; text-align: right">14.65 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;77.96%</td>
    <td style="white-space: nowrap; text-align: right">9.82 s</td>
    <td style="white-space: nowrap; text-align: right">31.64 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">with cache</td>
    <td style="white-space: nowrap;text-align: right">4.68 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">without cache</td>
    <td style="white-space: nowrap; text-align: right">0.00007 K</td>
    <td style="white-space: nowrap; text-align: right">68577.15x</td>
  </tr>

</table>