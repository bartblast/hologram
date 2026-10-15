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
    <td style="white-space: nowrap; text-align: right">1630.68</td>
    <td style="white-space: nowrap; text-align: right">0.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;17.30%</td>
    <td style="white-space: nowrap; text-align: right">0.58 ms</td>
    <td style="white-space: nowrap; text-align: right">1.11 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">106.00</td>
    <td style="white-space: nowrap; text-align: right">9.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.02%</td>
    <td style="white-space: nowrap; text-align: right">9.26 ms</td>
    <td style="white-space: nowrap; text-align: right">11.20 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">26.23</td>
    <td style="white-space: nowrap; text-align: right">38.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.58%</td>
    <td style="white-space: nowrap; text-align: right">35.24 ms</td>
    <td style="white-space: nowrap; text-align: right">63.59 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module no page uses edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">13.16</td>
    <td style="white-space: nowrap; text-align: right">75.98 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.38%</td>
    <td style="white-space: nowrap; text-align: right">75.22 ms</td>
    <td style="white-space: nowrap; text-align: right">111.53 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.90</td>
    <td style="white-space: nowrap; text-align: right">77.51 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;6.04%</td>
    <td style="white-space: nowrap; text-align: right">75.85 ms</td>
    <td style="white-space: nowrap; text-align: right">99.62 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">3.52</td>
    <td style="white-space: nowrap; text-align: right">284.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.91%</td>
    <td style="white-space: nowrap; text-align: right">283.39 ms</td>
    <td style="white-space: nowrap; text-align: right">304.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.39</td>
    <td style="white-space: nowrap; text-align: right">2592.58 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.20%</td>
    <td style="white-space: nowrap; text-align: right">2589.86 ms</td>
    <td style="white-space: nowrap; text-align: right">2631.87 ms</td>
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
    <td style="white-space: nowrap;text-align: right">1630.68</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">106.00</td>
    <td style="white-space: nowrap; text-align: right">15.38x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module changed, Hologram off</td>
    <td style="white-space: nowrap; text-align: right">26.23</td>
    <td style="white-space: nowrap; text-align: right">62.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">a module no page uses edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">13.16</td>
    <td style="white-space: nowrap; text-align: right">123.89x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">12.90</td>
    <td style="white-space: nowrap; text-align: right">126.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">3.52</td>
    <td style="white-space: nowrap; text-align: right">463.32x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.39</td>
    <td style="white-space: nowrap; text-align: right">4227.67x</td>
  </tr>

</table>