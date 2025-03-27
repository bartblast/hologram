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
    <td style="white-space: nowrap">1 vertex</td>
    <td style="white-space: nowrap; text-align: right">51.43</td>
    <td style="white-space: nowrap; text-align: right">19.44 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.68%</td>
    <td style="white-space: nowrap; text-align: right">19.37 ms</td>
    <td style="white-space: nowrap; text-align: right">22.09 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">31.57</td>
    <td style="white-space: nowrap; text-align: right">31.67 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.11%</td>
    <td style="white-space: nowrap; text-align: right">31.12 ms</td>
    <td style="white-space: nowrap; text-align: right">43.00 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">17.33</td>
    <td style="white-space: nowrap; text-align: right">57.70 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.04%</td>
    <td style="white-space: nowrap; text-align: right">56.94 ms</td>
    <td style="white-space: nowrap; text-align: right">70.88 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">9.14</td>
    <td style="white-space: nowrap; text-align: right">109.38 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.62%</td>
    <td style="white-space: nowrap; text-align: right">108.97 ms</td>
    <td style="white-space: nowrap; text-align: right">121.64 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">4.76</td>
    <td style="white-space: nowrap; text-align: right">210.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.11%</td>
    <td style="white-space: nowrap; text-align: right">209.19 ms</td>
    <td style="white-space: nowrap; text-align: right">230.95 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">2.49</td>
    <td style="white-space: nowrap; text-align: right">402.17 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.54%</td>
    <td style="white-space: nowrap; text-align: right">399.28 ms</td>
    <td style="white-space: nowrap; text-align: right">450.46 ms</td>
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
    <td style="white-space: nowrap;text-align: right">51.43</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">2 vertices</td>
    <td style="white-space: nowrap; text-align: right">31.57</td>
    <td style="white-space: nowrap; text-align: right">1.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">4 vertices</td>
    <td style="white-space: nowrap; text-align: right">17.33</td>
    <td style="white-space: nowrap; text-align: right">2.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">8 vertices</td>
    <td style="white-space: nowrap; text-align: right">9.14</td>
    <td style="white-space: nowrap; text-align: right">5.63x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">16 vertices</td>
    <td style="white-space: nowrap; text-align: right">4.76</td>
    <td style="white-space: nowrap; text-align: right">10.81x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">32 vertices</td>
    <td style="white-space: nowrap; text-align: right">2.49</td>
    <td style="white-space: nowrap; text-align: right">20.68x</td>
  </tr>

</table>