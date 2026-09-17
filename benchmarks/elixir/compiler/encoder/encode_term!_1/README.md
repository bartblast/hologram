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
    <td style="white-space: nowrap; text-align: right">12393.06</td>
    <td style="white-space: nowrap; text-align: right">0.0807 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;10.55%</td>
    <td style="white-space: nowrap; text-align: right">0.0748 ms</td>
    <td style="white-space: nowrap; text-align: right">0.108 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">2754.18</td>
    <td style="white-space: nowrap; text-align: right">0.36 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.40%</td>
    <td style="white-space: nowrap; text-align: right">0.36 ms</td>
    <td style="white-space: nowrap; text-align: right">0.38 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1530.09</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.93%</td>
    <td style="white-space: nowrap; text-align: right">0.65 ms</td>
    <td style="white-space: nowrap; text-align: right">0.71 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">680.12</td>
    <td style="white-space: nowrap; text-align: right">1.47 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.98%</td>
    <td style="white-space: nowrap; text-align: right">1.47 ms</td>
    <td style="white-space: nowrap; text-align: right">1.54 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">623.51</td>
    <td style="white-space: nowrap; text-align: right">1.60 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.37%</td>
    <td style="white-space: nowrap; text-align: right">1.60 ms</td>
    <td style="white-space: nowrap; text-align: right">1.67 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">319.21</td>
    <td style="white-space: nowrap; text-align: right">3.13 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.63%</td>
    <td style="white-space: nowrap; text-align: right">3.11 ms</td>
    <td style="white-space: nowrap; text-align: right">3.47 ms</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">146.78</td>
    <td style="white-space: nowrap; text-align: right">6.81 ms</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;2.72%</td>
    <td style="white-space: nowrap; text-align: right">6.84 ms</td>
    <td style="white-space: nowrap; text-align: right">7.18 ms</td>
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
    <td style="white-space: nowrap;text-align: right">12393.06</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">200 KB binary that is not text</td>
    <td style="white-space: nowrap; text-align: right">2754.18</td>
    <td style="white-space: nowrap; text-align: right">4.5x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">80 KB of text</td>
    <td style="white-space: nowrap; text-align: right">1530.09</td>
    <td style="white-space: nowrap; text-align: right">8.1x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">256 KB of non-ASCII text</td>
    <td style="white-space: nowrap; text-align: right">680.12</td>
    <td style="white-space: nowrap; text-align: right">18.22x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">160 KB of text</td>
    <td style="white-space: nowrap; text-align: right">623.51</td>
    <td style="white-space: nowrap; text-align: right">19.88x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">320 KB of text</td>
    <td style="white-space: nowrap; text-align: right">319.21</td>
    <td style="white-space: nowrap; text-align: right">38.82x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">640 KB of text</td>
    <td style="white-space: nowrap; text-align: right">146.78</td>
    <td style="white-space: nowrap; text-align: right">84.43x</td>
  </tr>

</table>