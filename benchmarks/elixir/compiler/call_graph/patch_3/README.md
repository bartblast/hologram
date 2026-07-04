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
    <td style="white-space: nowrap">no module changes</td>
    <td style="white-space: nowrap; text-align: right">130975.29</td>
    <td style="white-space: nowrap; text-align: right">0.00764 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.98%</td>
    <td style="white-space: nowrap; text-align: right">0.00733 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0110 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2310.00</td>
    <td style="white-space: nowrap; text-align: right">0.43 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;7.88%</td>
    <td style="white-space: nowrap; text-align: right">0.43 ms</td>
    <td style="white-space: nowrap; text-align: right">0.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">65.77</td>
    <td style="white-space: nowrap; text-align: right">15.20 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.10%</td>
    <td style="white-space: nowrap; text-align: right">15.96 ms</td>
    <td style="white-space: nowrap; text-align: right">19.47 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">63.84</td>
    <td style="white-space: nowrap; text-align: right">15.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;31.96%</td>
    <td style="white-space: nowrap; text-align: right">17.60 ms</td>
    <td style="white-space: nowrap; text-align: right">21.18 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">58.58</td>
    <td style="white-space: nowrap; text-align: right">17.07 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;21.55%</td>
    <td style="white-space: nowrap; text-align: right">17.69 ms</td>
    <td style="white-space: nowrap; text-align: right">23.37 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">38.63</td>
    <td style="white-space: nowrap; text-align: right">25.89 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;22.40%</td>
    <td style="white-space: nowrap; text-align: right">25.04 ms</td>
    <td style="white-space: nowrap; text-align: right">46.98 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">22.03</td>
    <td style="white-space: nowrap; text-align: right">45.40 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.89%</td>
    <td style="white-space: nowrap; text-align: right">45.59 ms</td>
    <td style="white-space: nowrap; text-align: right">50.99 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.69</td>
    <td style="white-space: nowrap; text-align: right">78.77 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.63%</td>
    <td style="white-space: nowrap; text-align: right">79.34 ms</td>
    <td style="white-space: nowrap; text-align: right">87.36 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.40</td>
    <td style="white-space: nowrap; text-align: right">227.31 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.59%</td>
    <td style="white-space: nowrap; text-align: right">227.00 ms</td>
    <td style="white-space: nowrap; text-align: right">246.52 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">1409.22 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.74%</td>
    <td style="white-space: nowrap; text-align: right">1401.83 ms</td>
    <td style="white-space: nowrap; text-align: right">1454.87 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.65</td>
    <td style="white-space: nowrap; text-align: right">1528.69 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.48%</td>
    <td style="white-space: nowrap; text-align: right">1517.89 ms</td>
    <td style="white-space: nowrap; text-align: right">1558.70 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.27</td>
    <td style="white-space: nowrap; text-align: right">3702.16 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.29%</td>
    <td style="white-space: nowrap; text-align: right">3706.41 ms</td>
    <td style="white-space: nowrap; text-align: right">3710.07 ms</td>
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
    <td style="white-space: nowrap;text-align: right">130975.29</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module added </td>
    <td style="white-space: nowrap; text-align: right">2310.00</td>
    <td style="white-space: nowrap; text-align: right">56.7x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module removed </td>
    <td style="white-space: nowrap; text-align: right">65.77</td>
    <td style="white-space: nowrap; text-align: right">1991.36x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 module edited </td>
    <td style="white-space: nowrap; text-align: right">63.84</td>
    <td style="white-space: nowrap; text-align: right">2051.71x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1 added, 1 removed, 1 edited</td>
    <td style="white-space: nowrap; text-align: right">58.58</td>
    <td style="white-space: nowrap; text-align: right">2235.74x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">3 added, 3 removed, 3 edited</td>
    <td style="white-space: nowrap; text-align: right">38.63</td>
    <td style="white-space: nowrap; text-align: right">3390.77x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">10 added, 10 removed, 10 edited</td>
    <td style="white-space: nowrap; text-align: right">22.03</td>
    <td style="white-space: nowrap; text-align: right">5945.92x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">1% added, 1% removed, 1% edited</td>
    <td style="white-space: nowrap; text-align: right">12.69</td>
    <td style="white-space: nowrap; text-align: right">10317.51x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules added</td>
    <td style="white-space: nowrap; text-align: right">4.40</td>
    <td style="white-space: nowrap; text-align: right">29772.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules removed</td>
    <td style="white-space: nowrap; text-align: right">0.71</td>
    <td style="white-space: nowrap; text-align: right">184573.2x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">33% added, 33% removed, 34% edited</td>
    <td style="white-space: nowrap; text-align: right">0.65</td>
    <td style="white-space: nowrap; text-align: right">200220.61x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">100% modules edited</td>
    <td style="white-space: nowrap; text-align: right">0.27</td>
    <td style="white-space: nowrap; text-align: right">484891.06x</td>
  </tr>

</table>