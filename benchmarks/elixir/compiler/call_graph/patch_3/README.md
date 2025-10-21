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
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">175303.86</td>
    <td style="white-space: nowrap; text-align: right">0.00570 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;32.26%</td>
    <td style="white-space: nowrap; text-align: right">0.00525 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0120 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2942.44</td>
    <td style="white-space: nowrap; text-align: right">0.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.15%</td>
    <td style="white-space: nowrap; text-align: right">0.33 ms</td>
    <td style="white-space: nowrap; text-align: right">0.74 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">224.96</td>
    <td style="white-space: nowrap; text-align: right">4.45 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;73.69%</td>
    <td style="white-space: nowrap; text-align: right">2.11 ms</td>
    <td style="white-space: nowrap; text-align: right">13.04 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">174.71</td>
    <td style="white-space: nowrap; text-align: right">5.72 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;56.46%</td>
    <td style="white-space: nowrap; text-align: right">3.83 ms</td>
    <td style="white-space: nowrap; text-align: right">13.56 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">151.36</td>
    <td style="white-space: nowrap; text-align: right">6.61 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;42.92%</td>
    <td style="white-space: nowrap; text-align: right">4.65 ms</td>
    <td style="white-space: nowrap; text-align: right">12.20 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">86.75</td>
    <td style="white-space: nowrap; text-align: right">11.53 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.84%</td>
    <td style="white-space: nowrap; text-align: right">9.90 ms</td>
    <td style="white-space: nowrap; text-align: right">17.28 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">31.51</td>
    <td style="white-space: nowrap; text-align: right">31.74 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.68%</td>
    <td style="white-space: nowrap; text-align: right">31.77 ms</td>
    <td style="white-space: nowrap; text-align: right">38.40 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">23.07</td>
    <td style="white-space: nowrap; text-align: right">43.34 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.93%</td>
    <td style="white-space: nowrap; text-align: right">43.61 ms</td>
    <td style="white-space: nowrap; text-align: right">47.72 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">9.22</td>
    <td style="white-space: nowrap; text-align: right">108.48 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.53%</td>
    <td style="white-space: nowrap; text-align: right">108.11 ms</td>
    <td style="white-space: nowrap; text-align: right">123.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.91</td>
    <td style="white-space: nowrap; text-align: right">1103.56 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.08%</td>
    <td style="white-space: nowrap; text-align: right">1099.71 ms</td>
    <td style="white-space: nowrap; text-align: right">1124.22 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.85</td>
    <td style="white-space: nowrap; text-align: right">1178.18 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.74%</td>
    <td style="white-space: nowrap; text-align: right">1151.89 ms</td>
    <td style="white-space: nowrap; text-align: right">1325.87 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.35</td>
    <td style="white-space: nowrap; text-align: right">2886.80 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.56%</td>
    <td style="white-space: nowrap; text-align: right">2887.42 ms</td>
    <td style="white-space: nowrap; text-align: right">2904.84 ms</td>
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
    <td style="white-space: nowrap;text-align: right">175303.86</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2942.44</td>
    <td style="white-space: nowrap; text-align: right">59.58x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">224.96</td>
    <td style="white-space: nowrap; text-align: right">779.27x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">174.71</td>
    <td style="white-space: nowrap; text-align: right">1003.42x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">151.36</td>
    <td style="white-space: nowrap; text-align: right">1158.18x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">86.75</td>
    <td style="white-space: nowrap; text-align: right">2020.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">31.51</td>
    <td style="white-space: nowrap; text-align: right">5563.72x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">23.07</td>
    <td style="white-space: nowrap; text-align: right">7598.31x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">9.22</td>
    <td style="white-space: nowrap; text-align: right">19017.66x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.91</td>
    <td style="white-space: nowrap; text-align: right">193459.06x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.85</td>
    <td style="white-space: nowrap; text-align: right">206539.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.35</td>
    <td style="white-space: nowrap; text-align: right">506067.89x</td>
  </tr>

</table>