# Elixir Benchmarks

Last run: 2025-10-21 16:25:21 UTC

## Summary

Total benchmarks: 31
Successful: 31Warnings: 0Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.74      364.40 ms     ±3.94%      359.55 ms      415.70 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          1.62      618.39 ms     ±2.04%      614.92 ms      651.85 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          3.41      293.61 ms     ±1.71%      292.74 ms      315.46 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          5.19      192.70 ms     ±3.86%      192.40 ms      210.32 ms
```


### ✅ compiler » build_page_js_4

```
Name                      ips        average  deviation         median         99th %
build_page_js/4        120.92        8.27 ms    ±17.04%        9.26 ms       10.14 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          4.93      202.70 ms     ±3.37%      202.72 ms      224.34 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         51.23       19.52 ms    ±14.29%       17.89 ms       24.82 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file exists                24.40       40.99 ms     ±3.50%       40.74 ms       48.88 ms
dump dir doesn't exists                          24.17       41.38 ms     ±4.02%       41.02 ms       50.82 ms
dump dir exists, dump file doesn't exist         23.80       42.02 ms     ±3.41%       41.72 ms       45.85 ms

Comparison: 
dump dir exists, dump file exists                24.40
dump dir doesn't exists                          24.17 - 1.01x slower +0.39 ms
dump dir exists, dump file doesn't exist         23.80 - 1.03x slower +1.03 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         63.83       15.67 ms     ±1.79%       15.55 ms       16.54 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      244535.79     0.00409 ms    ±19.15%     0.00400 ms     0.00671 ms
1 module added                           1886.53        0.53 ms     ±2.16%        0.53 ms        0.56 ms
1 module removed                          530.03        1.89 ms     ±3.37%        1.87 ms        2.03 ms
1 module edited                           292.51        3.42 ms     ±6.52%        3.30 ms        3.87 ms
1 added, 1 removed, 1 edited              211.50        4.73 ms     ±5.52%        4.67 ms        5.65 ms
3 added, 3 removed, 3 edited               97.67       10.24 ms     ±1.53%       10.20 ms       10.62 ms
10 added, 10 removed, 10 edited            33.62       29.74 ms     ±1.14%       29.66 ms       30.81 ms
1% added, 1% removed, 1% edited            26.31       38.00 ms     ±1.52%       37.96 ms       39.35 ms
100% modules added                          2.04      489.16 ms     ±0.65%      489.20 ms      495.57 ms
33% added, 33% removed, 34% edited          0.86     1168.06 ms     ±6.34%     1138.06 ms     1306.51 ms
100% modules removed                        0.77     1303.94 ms     ±1.00%     1301.56 ms     1323.54 ms
100% modules edited                         0.32     3153.76 ms     ±3.09%     3108.66 ms     3265.48 ms

Comparison: 
no module changes                      244535.79
1 module added                           1886.53 - 129.62x slower +0.53 ms
1 module removed                          530.03 - 461.36x slower +1.88 ms
1 module edited                           292.51 - 836.00x slower +3.41 ms
1 added, 1 removed, 1 edited              211.50 - 1156.20x slower +4.72 ms
3 added, 3 removed, 3 edited               97.67 - 2503.64x slower +10.23 ms
10 added, 10 removed, 10 edited            33.62 - 7273.32x slower +29.74 ms
1% added, 1% removed, 1% edited            26.31 - 9293.17x slower +38.00 ms
100% modules added                          2.04 - 119617.82x slower +489.16 ms
33% added, 33% removed, 34% edited          0.86 - 285632.75x slower +1168.06 ms
100% modules removed                        0.77 - 318860.38x slower +1303.94 ms
100% modules edited                         0.32 - 771207.83x slower +3153.76 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        587.70        1.70 ms     ±4.11%        1.67 ms        1.94 ms
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2         17.99       55.59 ms     ±1.75%       55.35 ms       59.28 ms
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
1 vertex          87.94 K       11.37 μs    ±31.94%       10.38 μs       27.39 μs
2 vertices        49.28 K       20.29 μs   ±148.42%       16.96 μs       43.58 μs
4 vertices        31.63 K       31.62 μs    ±23.84%       29.88 μs       61.66 μs
8 vertices        16.39 K       61.00 μs    ±15.95%       58.94 μs      104.61 μs
16 vertices       10.59 K       94.44 μs    ±13.98%       91.15 μs      145.47 μs
32 vertices        4.11 K      243.38 μs    ±17.18%      234.96 μs      385.65 μs

Comparison: 
1 vertex          87.94 K
2 vertices        49.28 K - 1.78x slower +8.92 μs
4 vertices        31.63 K - 2.78x slower +20.25 μs
8 vertices        16.39 K - 5.36x slower +49.63 μs
16 vertices       10.59 K - 8.30x slower +83.07 μs
32 vertices        4.11 K - 21.40x slower +232.01 μs
```


### ✅ compiler » create_page_entry_files_4

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/4          1.66      602.97 ms     ±4.69%      584.63 ms      645.45 ms
```


### ✅ compiler » create_runtime_entry_file_3

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/3         21.53       46.45 ms     ±5.40%       46.39 ms       58.02 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.69 K      213.22 μs     ±5.95%      213.63 μs      248.25 μs
100% modules added                        3.69 K      271.17 μs    ±14.52%      246.67 μs      385.17 μs
33% added, 33% removed, 34% edited        2.85 K      351.41 μs     ±9.11%      354.88 μs      434.82 μs
3 added, 3 removed, 3 edited              1.88 K      533.02 μs     ±3.34%      529.09 μs      598.99 μs
1 module removed                          1.82 K      549.51 μs     ±4.05%      545.67 μs      636.76 μs
100% modules edited                       1.81 K      552.20 μs     ±4.74%      550.13 μs      673.84 μs
no module changes                         1.81 K      553.59 μs     ±4.21%      553.29 μs      624.75 μs
1 module edited                           1.78 K      560.23 μs     ±4.57%      554.08 μs      652.82 μs
1 module added                            1.77 K      565.67 μs     ±3.01%      563.58 μs      636.25 μs
1% added, 1% removed, 1% edited           1.75 K      572.23 μs     ±4.56%      573.54 μs      660.83 μs
10 added, 10 removed, 10 edited           1.74 K      573.14 μs     ±3.82%      572.96 μs      648.94 μs
1 added, 1 removed, 1 edited              1.69 K      593.25 μs     ±4.29%      591.13 μs      684.86 μs

Comparison: 
100% modules removed                      4.69 K
100% modules added                        3.69 K - 1.27x slower +57.95 μs
33% added, 33% removed, 34% edited        2.85 K - 1.65x slower +138.19 μs
3 added, 3 removed, 3 edited              1.88 K - 2.50x slower +319.80 μs
1 module removed                          1.82 K - 2.58x slower +336.28 μs
100% modules edited                       1.81 K - 2.59x slower +338.97 μs
no module changes                         1.81 K - 2.60x slower +340.37 μs
1 module edited                           1.78 K - 2.63x slower +347.01 μs
1 module added                            1.77 K - 2.65x slower +352.45 μs
1% added, 1% removed, 1% edited           1.75 K - 2.68x slower +359.01 μs
10 added, 10 removed, 10 edited           1.74 K - 2.69x slower +359.92 μs
1 added, 1 removed, 1 edited              1.69 K - 2.78x slower +380.03 μs
```


### ✅ compiler » format_files_2

```
Name                     ips        average  deviation         median         99th %
format_files/2          1.20      831.81 ms     ±1.28%      829.59 ms      849.20 ms
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install       14.28 K      0.00007 s     ±9.95%      0.00007 s      0.00009 s
do install     0.00016 K         6.18 s     ±8.01%         6.18 s         6.53 s

Comparison: 
no install       14.28 K
do install     0.00016 K - 88317.14x slower +6.18 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      203.79 K     0.00491 ms   ±141.11%     0.00463 ms      0.0105 ms
do load      0.0141 K       70.72 ms     ±2.07%       70.26 ms       76.08 ms

Comparison: 
no load      203.79 K
do load      0.0141 K - 14411.37x slower +70.71 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      106.46 K     0.00939 ms    ±67.07%     0.00912 ms      0.0130 ms
do load     0.00216 K      463.34 ms     ±1.94%      460.90 ms      486.37 ms

Comparison: 
no load      106.46 K
do load     0.00216 K - 49327.39x slower +463.33 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      110.55 K        9.05 μs    ±69.76%        8.67 μs       14.08 μs
do load        2.16 K      463.00 μs     ±3.51%      460.58 μs      552.92 μs

Comparison: 
no load      110.55 K
do load        2.16 K - 51.18x slower +453.95 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      162.07 K        6.17 μs   ±186.92%        6.08 μs        6.83 μs
```


### ✅ mix » tasks » compileroothologram

```
Name                ips        average  deviation         median         99th %
has cache          0.54         1.84 s     ±1.91%         1.83 s         1.89 s
no cache           0.21         4.71 s     ±0.08%         4.71 s         4.71 s

Comparison: 
has cache          0.54
no cache           0.21 - 2.56x slower +2.87 s
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           169.96 M        5.88 ns ±37504.83%        4.20 ns       16.60 ns
is atom                10.05 M       99.54 ns ±46524.29%          42 ns         125 ns
is Erlang module        9.95 M      100.47 ns ±47469.90%          42 ns          84 ns
is Elixir module        7.87 M      127.13 ns ±39570.58%          83 ns         125 ns

Comparison: 
is not atom           169.96 M
is atom                10.05 M - 16.92x slower +93.66 ns
is Erlang module        9.95 M - 17.08x slower +94.59 ns
is Elixir module        7.87 M - 21.61x slower +121.25 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           168.60 M        5.93 ns ±37056.96%        4.20 ns       16.60 ns
is Elixir module        9.78 M      102.26 ns ±36420.74%          42 ns          84 ns
is Erlang module        5.61 M      178.22 ns ±30167.66%          83 ns         125 ns
is atom               0.0753 M    13279.80 ns    ±53.88%       12958 ns       18083 ns

Comparison: 
is not atom           168.60 M
is Elixir module        9.78 M - 17.24x slower +96.33 ns
is Erlang module        5.61 M - 30.05x slower +172.29 ns
is atom               0.0753 M - 2239.00x slower +13273.87 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.60 M       64.11 ns ±55253.67%          42 ns          83 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.45 M       80.32 ns ±43807.55%          42 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         55.89       17.89 ms     ±7.25%       18.05 ms       20.44 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         53.90       18.55 ms     ±8.80%       18.95 ms       21.16 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        249.26        4.01 ms    ±11.32%        3.84 ms        5.38 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           159.67 M        6.26 ns ±37010.99%        4.20 ns       12.50 ns
is Erlang module       16.89 M       59.20 ns ±52809.09%          42 ns          42 ns
is Elixir module       16.82 M       59.45 ns ±51026.79%          42 ns          42 ns
is atom               0.0798 M    12524.91 ns    ±85.20%       12208 ns       19167 ns

Comparison: 
is not atom           159.67 M
is Erlang module       16.89 M - 9.45x slower +52.93 ns
is Elixir module       16.82 M - 9.49x slower +53.19 ns
is atom               0.0798 M - 1999.84x slower +12518.64 ns
```

