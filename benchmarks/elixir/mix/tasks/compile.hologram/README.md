Benchmark

mix compile.hologram

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
    <td style="white-space: nowrap">has cache</td>
    <td style="white-space: nowrap; text-align: right">0.48</td>
    <td style="white-space: nowrap; text-align: right">2.07 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.58%</td>
    <td style="white-space: nowrap; text-align: right">2.06 s</td>
    <td style="white-space: nowrap; text-align: right">2.17 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no cache</td>
    <td style="white-space: nowrap; text-align: right">0.0946</td>
    <td style="white-space: nowrap; text-align: right">10.57 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;72.78%</td>
    <td style="white-space: nowrap; text-align: right">10.57 s</td>
    <td style="white-space: nowrap; text-align: right">16.01 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">has cache</td>
    <td style="white-space: nowrap;text-align: right">0.48</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no cache</td>
    <td style="white-space: nowrap; text-align: right">0.0946</td>
    <td style="white-space: nowrap; text-align: right">5.12x</td>
  </tr>

</table>