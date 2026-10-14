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
    <td style="white-space: nowrap; text-align: right">1506.64</td>
    <td style="white-space: nowrap; text-align: right">0.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;29.87%</td>
    <td style="white-space: nowrap; text-align: right">0.61 ms</td>
    <td style="white-space: nowrap; text-align: right">1.16 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">96.48</td>
    <td style="white-space: nowrap; text-align: right">10.36 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.89%</td>
    <td style="white-space: nowrap; text-align: right">9.91 ms</td>
    <td style="white-space: nowrap; text-align: right">15.12 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">25.19</td>
    <td style="white-space: nowrap; text-align: right">39.70 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.89%</td>
    <td style="white-space: nowrap; text-align: right">35.44 ms</td>
    <td style="white-space: nowrap; text-align: right">78.12 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module no page uses edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.14</td>
    <td style="white-space: nowrap; text-align: right">82.38 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.69%</td>
    <td style="white-space: nowrap; text-align: right">81.59 ms</td>
    <td style="white-space: nowrap; text-align: right">105.76 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">11.71</td>
    <td style="white-space: nowrap; text-align: right">85.36 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.30%</td>
    <td style="white-space: nowrap; text-align: right">83.84 ms</td>
    <td style="white-space: nowrap; text-align: right">116.28 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">3.40</td>
    <td style="white-space: nowrap; text-align: right">294.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.62%</td>
    <td style="white-space: nowrap; text-align: right">293.01 ms</td>
    <td style="white-space: nowrap; text-align: right">322.04 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.38</td>
    <td style="white-space: nowrap; text-align: right">2616.21 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.30%</td>
    <td style="white-space: nowrap; text-align: right">2621.57 ms</td>
    <td style="white-space: nowrap; text-align: right">2647.84 ms</td>
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
    <td style="white-space: nowrap;text-align: right">1506.64</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">96.48</td>
    <td style="white-space: nowrap; text-align: right">15.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">25.19</td>
    <td style="white-space: nowrap; text-align: right">59.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module no page uses edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.14</td>
    <td style="white-space: nowrap; text-align: right">124.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">11.71</td>
    <td style="white-space: nowrap; text-align: right">128.61x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">3.40</td>
    <td style="white-space: nowrap; text-align: right">443.69x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.38</td>
    <td style="white-space: nowrap; text-align: right">3941.68x</td>
  </tr>

</table>