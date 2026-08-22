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
    <td style="white-space: nowrap; text-align: right">14345.84</td>
    <td style="white-space: nowrap; text-align: right">0.0697 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;14.24%</td>
    <td style="white-space: nowrap; text-align: right">0.0658 ms</td>
    <td style="white-space: nowrap; text-align: right">0.0940 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1756.43</td>
    <td style="white-space: nowrap; text-align: right">0.57 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.80%</td>
    <td style="white-space: nowrap; text-align: right">0.56 ms</td>
    <td style="white-space: nowrap; text-align: right">0.66 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">787.89</td>
    <td style="white-space: nowrap; text-align: right">1.27 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;9.02%</td>
    <td style="white-space: nowrap; text-align: right">1.26 ms</td>
    <td style="white-space: nowrap; text-align: right">1.38 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">703.70</td>
    <td style="white-space: nowrap; text-align: right">1.42 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;5.99%</td>
    <td style="white-space: nowrap; text-align: right">1.41 ms</td>
    <td style="white-space: nowrap; text-align: right">1.55 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">351.51</td>
    <td style="white-space: nowrap; text-align: right">2.84 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;16.73%</td>
    <td style="white-space: nowrap; text-align: right">2.80 ms</td>
    <td style="white-space: nowrap; text-align: right">3.12 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">157.01</td>
    <td style="white-space: nowrap; text-align: right">6.37 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;15.12%</td>
    <td style="white-space: nowrap; text-align: right">6.28 ms</td>
    <td style="white-space: nowrap; text-align: right">8.05 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">66.40</td>
    <td style="white-space: nowrap; text-align: right">15.06 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;11.79%</td>
    <td style="white-space: nowrap; text-align: right">14.81 ms</td>
    <td style="white-space: nowrap; text-align: right">18.71 ms</td>
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
    <td style="white-space: nowrap;text-align: right">14345.84</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1756.43</td>
    <td style="white-space: nowrap; text-align: right">8.17x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">787.89</td>
    <td style="white-space: nowrap; text-align: right">18.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">703.70</td>
    <td style="white-space: nowrap; text-align: right">20.39x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">351.51</td>
    <td style="white-space: nowrap; text-align: right">40.81x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">157.01</td>
    <td style="white-space: nowrap; text-align: right">91.37x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">66.40</td>
    <td style="white-space: nowrap; text-align: right">216.06x</td>
  </tr>

</table>