Benchmark

Hologram.Compiler.QueryExtractor.validate_slot_bindings!/1

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
    <td style="white-space: nowrap">no parameterized captures</td>
    <td style="white-space: nowrap; text-align: right">8.38 M</td>
    <td style="white-space: nowrap; text-align: right">0.119 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4527.93%</td>
    <td style="white-space: nowrap; text-align: right">0.0830 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">0.167 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parameterized capture</td>
    <td style="white-space: nowrap; text-align: right">0.00626 M</td>
    <td style="white-space: nowrap; text-align: right">159.63 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;116.88%</td>
    <td style="white-space: nowrap; text-align: right">140.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">422.49 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no parameterized captures</td>
    <td style="white-space: nowrap;text-align: right">8.38 M</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">parameterized capture</td>
    <td style="white-space: nowrap; text-align: right">0.00626 M</td>
    <td style="white-space: nowrap; text-align: right">1338.03x</td>
  </tr>

</table>