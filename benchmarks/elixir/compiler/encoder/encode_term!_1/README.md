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
    <td style="white-space: nowrap; text-align: right">13378.45</td>
    <td style="white-space: nowrap; text-align: right">0.0747 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;45.34%</td>
    <td style="white-space: nowrap; text-align: right">0.0715 ms</td>
    <td style="white-space: nowrap; text-align: right">0.125 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1528.96</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;53.53%</td>
    <td style="white-space: nowrap; text-align: right">0.64 ms</td>
    <td style="white-space: nowrap; text-align: right">0.86 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">779.68</td>
    <td style="white-space: nowrap; text-align: right">1.28 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.60%</td>
    <td style="white-space: nowrap; text-align: right">1.28 ms</td>
    <td style="white-space: nowrap; text-align: right">1.45 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">669.39</td>
    <td style="white-space: nowrap; text-align: right">1.49 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;19.29%</td>
    <td style="white-space: nowrap; text-align: right">1.47 ms</td>
    <td style="white-space: nowrap; text-align: right">2.19 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">305.59</td>
    <td style="white-space: nowrap; text-align: right">3.27 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;23.81%</td>
    <td style="white-space: nowrap; text-align: right">3.26 ms</td>
    <td style="white-space: nowrap; text-align: right">3.88 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">150.57</td>
    <td style="white-space: nowrap; text-align: right">6.64 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;18.58%</td>
    <td style="white-space: nowrap; text-align: right">6.54 ms</td>
    <td style="white-space: nowrap; text-align: right">7.57 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">62.29</td>
    <td style="white-space: nowrap; text-align: right">16.05 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;28.78%</td>
    <td style="white-space: nowrap; text-align: right">15.24 ms</td>
    <td style="white-space: nowrap; text-align: right">27.74 ms</td>
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
    <td style="white-space: nowrap;text-align: right">13378.45</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1528.96</td>
    <td style="white-space: nowrap; text-align: right">8.75x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">779.68</td>
    <td style="white-space: nowrap; text-align: right">17.16x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">669.39</td>
    <td style="white-space: nowrap; text-align: right">19.99x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">305.59</td>
    <td style="white-space: nowrap; text-align: right">43.78x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">150.57</td>
    <td style="white-space: nowrap; text-align: right">88.85x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">62.29</td>
    <td style="white-space: nowrap; text-align: right">214.76x</td>
  </tr>

</table>