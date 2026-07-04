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
    <td style="white-space: nowrap">has cache</td>
    <td style="white-space: nowrap; text-align: right">47.64 K</td>
    <td style="white-space: nowrap; text-align: right">20.99 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;43.25%</td>
    <td style="white-space: nowrap; text-align: right">19.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">44.83 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no cache</td>
    <td style="white-space: nowrap; text-align: right">30.16 K</td>
    <td style="white-space: nowrap; text-align: right">33.15 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;34.48%</td>
    <td style="white-space: nowrap; text-align: right">30.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">56.22 &micro;s</td>
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
    <td style="white-space: nowrap;text-align: right">47.64 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">no cache</td>
    <td style="white-space: nowrap; text-align: right">30.16 K</td>
    <td style="white-space: nowrap; text-align: right">1.58x</td>
  </tr>

</table>