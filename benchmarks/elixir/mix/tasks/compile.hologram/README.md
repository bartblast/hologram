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
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.59</td>
    <td style="white-space: nowrap; text-align: right">79.41 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.37%</td>
    <td style="white-space: nowrap; text-align: right">78.54 ms</td>
    <td style="white-space: nowrap; text-align: right">104.75 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">5.45</td>
    <td style="white-space: nowrap; text-align: right">183.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.84%</td>
    <td style="white-space: nowrap; text-align: right">180.65 ms</td>
    <td style="white-space: nowrap; text-align: right">233.14 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">2.68</td>
    <td style="white-space: nowrap; text-align: right">372.92 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.60%</td>
    <td style="white-space: nowrap; text-align: right">370.25 ms</td>
    <td style="white-space: nowrap; text-align: right">398.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.37</td>
    <td style="white-space: nowrap; text-align: right">2680.35 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.46%</td>
    <td style="white-space: nowrap; text-align: right">2553.84 ms</td>
    <td style="white-space: nowrap; text-align: right">3097.89 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap;text-align: right">12.59</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">5.45</td>
    <td style="white-space: nowrap; text-align: right">2.31x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">2.68</td>
    <td style="white-space: nowrap; text-align: right">4.7x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.37</td>
    <td style="white-space: nowrap; text-align: right">33.76x</td>
  </tr>

</table>