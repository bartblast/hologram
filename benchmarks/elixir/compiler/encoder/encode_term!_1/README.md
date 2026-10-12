Benchmark

Hologram.Compiler.Encoder.encode_term!/1

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
    <td style="white-space: nowrap">10 KB of text</td>
    <td style="white-space: nowrap; text-align: right">12272.69</td>
    <td style="white-space: nowrap; text-align: right">0.0815 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.11%</td>
    <td style="white-space: nowrap; text-align: right">0.0769 ms</td>
    <td style="white-space: nowrap; text-align: right">0.109 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">2656.65</td>
    <td style="white-space: nowrap; text-align: right">0.38 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;8.84%</td>
    <td style="white-space: nowrap; text-align: right">0.36 ms</td>
    <td style="white-space: nowrap; text-align: right">0.47 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1524.40</td>
    <td style="white-space: nowrap; text-align: right">0.66 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.12%</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
    <td style="white-space: nowrap; text-align: right">0.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">680.95</td>
    <td style="white-space: nowrap; text-align: right">1.47 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.85%</td>
    <td style="white-space: nowrap; text-align: right">1.47 ms</td>
    <td style="white-space: nowrap; text-align: right">1.51 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">610.33</td>
    <td style="white-space: nowrap; text-align: right">1.64 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.48%</td>
    <td style="white-space: nowrap; text-align: right">1.62 ms</td>
    <td style="white-space: nowrap; text-align: right">1.77 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">323.23</td>
    <td style="white-space: nowrap; text-align: right">3.09 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.00%</td>
    <td style="white-space: nowrap; text-align: right">3.09 ms</td>
    <td style="white-space: nowrap; text-align: right">3.18 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">144.64</td>
    <td style="white-space: nowrap; text-align: right">6.91 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.55%</td>
    <td style="white-space: nowrap; text-align: right">6.93 ms</td>
    <td style="white-space: nowrap; text-align: right">7.39 ms</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">10 KB of text</td>
    <td style="white-space: nowrap;text-align: right">12272.69</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">2656.65</td>
    <td style="white-space: nowrap; text-align: right">4.62x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1524.40</td>
    <td style="white-space: nowrap; text-align: right">8.05x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">680.95</td>
    <td style="white-space: nowrap; text-align: right">18.02x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">610.33</td>
    <td style="white-space: nowrap; text-align: right">20.11x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">323.23</td>
    <td style="white-space: nowrap; text-align: right">37.97x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">144.64</td>
    <td style="white-space: nowrap; text-align: right">84.85x</td>
  </tr>

</table>