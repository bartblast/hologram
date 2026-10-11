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
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap; text-align: right">0.74</td>
    <td style="white-space: nowrap; text-align: right">1.36 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;3.10%</td>
    <td style="white-space: nowrap; text-align: right">1.34 s</td>
    <td style="white-space: nowrap; text-align: right">1.43 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">0.69</td>
    <td style="white-space: nowrap; text-align: right">1.45 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;4.97%</td>
    <td style="white-space: nowrap; text-align: right">1.39 s</td>
    <td style="white-space: nowrap; text-align: right">1.54 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">0.175</td>
    <td style="white-space: nowrap; text-align: right">5.71 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;1.52%</td>
    <td style="white-space: nowrap; text-align: right">5.71 s</td>
    <td style="white-space: nowrap; text-align: right">5.77 s</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.133</td>
    <td style="white-space: nowrap; text-align: right">7.50 s</td>
    <td style="white-space: nowrap; text-align: right">&plusmn;0.86%</td>
    <td style="white-space: nowrap; text-align: right">7.50 s</td>
    <td style="white-space: nowrap; text-align: right">7.55 s</td>
  </tr>

</table>


Run Time Comparison

<table style="width: 1%">
  <tr>
    <th>Name</th>
    <th style="text-align: right">IPS</th>
    <th style="text-align: right">Slower</th>
  <tr>
    <td style="white-space: nowrap">nothing changed, new VM</td>
    <td style="white-space: nowrap;text-align: right">0.74</td>
    <td>&nbsp;</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">nothing changed, same VM</td>
    <td style="white-space: nowrap; text-align: right">0.69</td>
    <td style="white-space: nowrap; text-align: right">1.07x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">one page edited, same VM</td>
    <td style="white-space: nowrap; text-align: right">0.175</td>
    <td style="white-space: nowrap; text-align: right">4.21x</td>
  </tr>

  <tr>
    <td style="white-space: nowrap">cold</td>
    <td style="white-space: nowrap; text-align: right">0.133</td>
    <td style="white-space: nowrap; text-align: right">5.54x</td>
  </tr>

</table>