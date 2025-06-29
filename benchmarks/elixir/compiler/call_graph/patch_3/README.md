Benchmark

Hologram.Compiler.CallGraph.patch/3

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
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">289993.52</td>
    <td style="white-space: nowrap; text-align: right">0.00000 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.91%</td>
    <td style="white-space: nowrap; text-align: right">0.00000 s</td>
    <td style="white-space: nowrap; text-align: right">0.00001 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">181.67</td>
    <td style="white-space: nowrap; text-align: right">0.00550 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.47%</td>
    <td style="white-space: nowrap; text-align: right">0.00548 s</td>
    <td style="white-space: nowrap; text-align: right">0.00602 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">18.17</td>
    <td style="white-space: nowrap; text-align: right">0.0550 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.62%</td>
    <td style="white-space: nowrap; text-align: right">0.0547 s</td>
    <td style="white-space: nowrap; text-align: right">0.0577 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated </td>
    <td style="white-space: nowrap; text-align: right">16.12</td>
    <td style="white-space: nowrap; text-align: right">0.0620 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.29%</td>
    <td style="white-space: nowrap; text-align: right">0.0611 s</td>
    <td style="white-space: nowrap; text-align: right">0.0680 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.04</td>
    <td style="white-space: nowrap; text-align: right">0.96 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.25%</td>
    <td style="white-space: nowrap; text-align: right">0.96 s</td>
    <td style="white-space: nowrap; text-align: right">0.99 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">0.87</td>
    <td style="white-space: nowrap; text-align: right">1.15 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.76%</td>
    <td style="white-space: nowrap; text-align: right">1.15 s</td>
    <td style="white-space: nowrap; text-align: right">1.18 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">0.83</td>
    <td style="white-space: nowrap; text-align: right">1.21 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.91%</td>
    <td style="white-space: nowrap; text-align: right">1.21 s</td>
    <td style="white-space: nowrap; text-align: right">1.24 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">4.15 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.23%</td>
    <td style="white-space: nowrap; text-align: right">4.15 s</td>
    <td style="white-space: nowrap; text-align: right">4.23 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">4.17 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.95%</td>
    <td style="white-space: nowrap; text-align: right">4.15 s</td>
    <td style="white-space: nowrap; text-align: right">4.34 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">0.00882</td>
    <td style="white-space: nowrap; text-align: right">113.41 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">113.41 s</td>
    <td style="white-space: nowrap; text-align: right">113.41 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.00597</td>
    <td style="white-space: nowrap; text-align: right">167.41 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">167.41 s</td>
    <td style="white-space: nowrap; text-align: right">167.41 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">0.00324</td>
    <td style="white-space: nowrap; text-align: right">308.66 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.00%</td>
    <td style="white-space: nowrap; text-align: right">308.66 s</td>
    <td style="white-space: nowrap; text-align: right">308.66 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap;text-align: right">289993.52</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">181.67</td>
    <td style="white-space: nowrap; text-align: right">1596.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">18.17</td>
    <td style="white-space: nowrap; text-align: right">15961.45x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module updated </td>
    <td style="white-space: nowrap; text-align: right">16.12</td>
    <td style="white-space: nowrap; text-align: right">17987.96x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 updated</td>
    <td style="white-space: nowrap; text-align: right">1.04</td>
    <td style="white-space: nowrap; text-align: right">277621.26x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 updated</td>
    <td style="white-space: nowrap; text-align: right">0.87</td>
    <td style="white-space: nowrap; text-align: right">333432.28x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">0.83</td>
    <td style="white-space: nowrap; text-align: right">351402.03x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% updated</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">1202952.59x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 updated</td>
    <td style="white-space: nowrap; text-align: right">0.24</td>
    <td style="white-space: nowrap; text-align: right">1207855.35x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% updated</td>
    <td style="white-space: nowrap; text-align: right">0.00882</td>
    <td style="white-space: nowrap; text-align: right">32888978.55x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.00597</td>
    <td style="white-space: nowrap; text-align: right">48546660.13x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules updated</td>
    <td style="white-space: nowrap; text-align: right">0.00324</td>
    <td style="white-space: nowrap; text-align: right">89509251.25x</td>
  </tr>

</table>