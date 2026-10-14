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
    <td style="white-space: nowrap">nothing changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">1393.07</td>
    <td style="white-space: nowrap; text-align: right">0.72 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;34.07%</td>
    <td style="white-space: nowrap; text-align: right">0.61 ms</td>
    <td style="white-space: nowrap; text-align: right">1.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">90.74</td>
    <td style="white-space: nowrap; text-align: right">11.02 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.79%</td>
    <td style="white-space: nowrap; text-align: right">11.07 ms</td>
    <td style="white-space: nowrap; text-align: right">14.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">22.86</td>
    <td style="white-space: nowrap; text-align: right">43.75 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.65%</td>
    <td style="white-space: nowrap; text-align: right">38.96 ms</td>
    <td style="white-space: nowrap; text-align: right">182.59 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.02</td>
    <td style="white-space: nowrap; text-align: right">83.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.40%</td>
    <td style="white-space: nowrap; text-align: right">82.01 ms</td>
    <td style="white-space: nowrap; text-align: right">118.97 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">2.66</td>
    <td style="white-space: nowrap; text-align: right">376.64 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.15%</td>
    <td style="white-space: nowrap; text-align: right">376.00 ms</td>
    <td style="white-space: nowrap; text-align: right">409.57 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.38</td>
    <td style="white-space: nowrap; text-align: right">2665.75 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.22%</td>
    <td style="white-space: nowrap; text-align: right">2664.02 ms</td>
    <td style="white-space: nowrap; text-align: right">2805.18 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">nothing changed, Hologram off</td>
    <td style="white-space: nowrap;text-align: right">1393.07</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">90.74</td>
    <td style="white-space: nowrap; text-align: right">15.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">22.86</td>
    <td style="white-space: nowrap; text-align: right">60.95x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.02</td>
    <td style="white-space: nowrap; text-align: right">115.92x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">2.66</td>
    <td style="white-space: nowrap; text-align: right">524.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.38</td>
    <td style="white-space: nowrap; text-align: right">3713.57x</td>
  </tr>

</table>