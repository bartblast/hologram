Benchmark

Hologram.Compiler.CallGraph.remove_vertices/2

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
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">73.27 K</td>
    <td style="white-space: nowrap; text-align: right">13.65 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;34.93%</td>
    <td style="white-space: nowrap; text-align: right">12.06 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">27.39 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">50.82 K</td>
    <td style="white-space: nowrap; text-align: right">19.68 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.12%</td>
    <td style="white-space: nowrap; text-align: right">17.75 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">33.33 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">30.57 K</td>
    <td style="white-space: nowrap; text-align: right">32.72 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.23%</td>
    <td style="white-space: nowrap; text-align: right">30.54 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">47.92 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">16.20 K</td>
    <td style="white-space: nowrap; text-align: right">61.73 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;27.32%</td>
    <td style="white-space: nowrap; text-align: right">58.98 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">81.42 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.71 K</td>
    <td style="white-space: nowrap; text-align: right">93.38 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.65%</td>
    <td style="white-space: nowrap; text-align: right">91.08 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">114.41 &micro;s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.76 K</td>
    <td style="white-space: nowrap; text-align: right">265.64 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;12.93%</td>
    <td style="white-space: nowrap; text-align: right">260 &micro;s</td>
    <td style="white-space: nowrap; text-align: right">322.24 &micro;s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap;text-align: right">73.27 K</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">50.82 K</td>
    <td style="white-space: nowrap; text-align: right">1.44x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">30.57 K</td>
    <td style="white-space: nowrap; text-align: right">2.4x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">16.20 K</td>
    <td style="white-space: nowrap; text-align: right">4.52x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">10.71 K</td>
    <td style="white-space: nowrap; text-align: right">6.84x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">3.76 K</td>
    <td style="white-space: nowrap; text-align: right">19.46x</td>
  </tr>

</table>