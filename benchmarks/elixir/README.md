# Elixir Benchmarks

Last run: 2026-07-04 12:16:34 UTC

## Summary

Total benchmarks: 32

Successful: 32\
Warnings: 0\
Failed: 0

## Results

### ✅ commons » plt » dump_2

```
Name             ips        average  deviation         median         99th %
IR PLT          2.53      395.03 ms     ±3.59%      390.59 ms      427.42 ms
```


### ✅ compiler » build_call_graph_1

```
Name                         ips        average  deviation         median         99th %
build_call_graph/1          4.05      246.62 ms    ±12.04%      240.13 ms      375.15 ms
```


### ✅ compiler » build_ir_plt_0

```
Name                     ips        average  deviation         median         99th %
build_ir_plt/0          2.07      483.91 ms     ±1.40%      483.91 ms      499.31 ms
```


### ✅ compiler » build_module_digest_plt!_0

```
Name                                 ips        average  deviation         median         99th %
build_module_digest_plt!/0          4.21      237.26 ms     ±3.40%      237.14 ms      253.92 ms
```


### ✅ compiler » build_page_js_5

```
Name                      ips        average  deviation         median         99th %
build_page_js/5         70.57       14.17 ms    ±13.92%       14.89 ms       16.89 ms
```


### ✅ compiler » bundle_2

```
Name               ips        average  deviation         median         99th %
bundle/2          4.64      215.70 ms     ±2.99%      215.09 ms      237.55 ms
```


### ✅ compiler » call_graph » clone_1

```
Name              ips        average  deviation         median         99th %
clone/1         45.33       22.06 ms    ±13.76%       20.00 ms       27.48 ms
```


### ✅ compiler » call_graph » dump_2

```
Name                                               ips        average  deviation         median         99th %
dump dir exists, dump file doesn't exist         22.59       44.27 ms     ±2.69%       44.02 ms       53.73 ms
dump dir exists, dump file exists                22.35       44.73 ms     ±4.60%       44.35 ms       59.01 ms
dump dir doesn't exists                          21.63       46.23 ms     ±3.91%       45.93 ms       59.53 ms

Comparison: 
dump dir exists, dump file doesn't exist         22.59
dump dir exists, dump file exists                22.35 - 1.01x slower +0.47 ms
dump dir doesn't exists                          21.63 - 1.04x slower +1.96 ms
```


### ✅ compiler » call_graph » list_page_mfas_2

```
Name                       ips        average  deviation         median         99th %
list_page_mfas/2         47.91       20.87 ms    ±15.61%       22.35 ms       26.41 ms
```


### ✅ compiler » call_graph » list_runtime_mfas_1

```
Name                          ips        average  deviation         median         99th %
list_runtime_mfas/1         22.15       45.15 ms     ±7.04%       44.46 ms       53.67 ms
```


### ✅ compiler » call_graph » patch_3

```
Name                                         ips        average  deviation         median         99th %
no module changes                      130975.29     0.00764 ms    ±16.98%     0.00733 ms      0.0110 ms
1 module added                           2310.00        0.43 ms     ±7.88%        0.43 ms        0.51 ms
1 module removed                           65.77       15.20 ms    ±23.10%       15.96 ms       19.47 ms
1 module edited                            63.84       15.66 ms    ±31.96%       17.60 ms       21.18 ms
1 added, 1 removed, 1 edited               58.58       17.07 ms    ±21.55%       17.69 ms       23.37 ms
3 added, 3 removed, 3 edited               38.63       25.89 ms    ±22.40%       25.04 ms       46.98 ms
10 added, 10 removed, 10 edited            22.03       45.40 ms     ±3.89%       45.59 ms       50.99 ms
1% added, 1% removed, 1% edited            12.69       78.77 ms     ±5.63%       79.34 ms       87.36 ms
100% modules added                          4.40      227.31 ms     ±3.59%      227.00 ms      246.52 ms
100% modules removed                        0.71     1409.22 ms     ±1.74%     1401.83 ms     1454.87 ms
33% added, 33% removed, 34% edited          0.65     1528.69 ms     ±1.48%     1517.89 ms     1558.70 ms
100% modules edited                         0.27     3702.16 ms     ±0.29%     3706.41 ms     3710.07 ms

Comparison: 
no module changes                      130975.29
1 module added                           2310.00 - 56.70x slower +0.43 ms
1 module removed                           65.77 - 1991.36x slower +15.20 ms
1 module edited                            63.84 - 2051.71x slower +15.66 ms
1 added, 1 removed, 1 edited               58.58 - 2235.74x slower +17.06 ms
3 added, 3 removed, 3 edited               38.63 - 3390.77x slower +25.88 ms
10 added, 10 removed, 10 edited            22.03 - 5945.92x slower +45.39 ms
1% added, 1% removed, 1% edited            12.69 - 10317.51x slower +78.77 ms
100% modules added                          4.40 - 29772.22x slower +227.30 ms
100% modules removed                        0.71 - 184573.20x slower +1409.21 ms
33% added, 33% removed, 34% edited          0.65 - 200220.61x slower +1528.68 ms
100% modules edited                         0.27 - 484891.06x slower +3702.15 ms
```


### ✅ compiler » call_graph » remove_manually_ported_mfas_1

```
Name                                    ips        average  deviation         median         99th %
remove_manually_ported_mfas/1        1.11 M      897.99 ns    ±29.14%         875 ns     1775.20 ns
```


### ✅ compiler » call_graph » remove_runtime_mfas!_2

```
Name                             ips        average  deviation         median         99th %
remove_runtime_mfas!/2       75.38 K       13.27 μs    ±10.33%       12.96 μs       22.63 μs
```


### ✅ compiler » call_graph » remove_vertices_2

```
Name                  ips        average  deviation         median         99th %
2 vertices         1.72 M      580.59 ns    ±67.28%         542 ns     2024.90 ns
1 vertex           1.61 M      622.85 ns    ±57.85%         583 ns     2221.45 ns
4 vertices         1.33 M      752.06 ns    ±48.02%         708 ns        1917 ns
8 vertices         1.05 M      953.11 ns    ±28.89%         916 ns     1985.96 ns
16 vertices        0.82 M     1223.00 ns    ±28.19%        1167 ns     2314.41 ns
32 vertices        0.54 M     1861.07 ns    ±24.38%        1833 ns     3431.16 ns

Comparison: 
2 vertices         1.72 M
1 vertex           1.61 M - 1.07x slower +42.26 ns
4 vertices         1.33 M - 1.30x slower +171.48 ns
8 vertices         1.05 M - 1.64x slower +372.52 ns
16 vertices        0.82 M - 2.11x slower +642.41 ns
32 vertices        0.54 M - 3.21x slower +1280.48 ns
```


### ✅ compiler » call_graph » server_protocol_dispatch_types_2

```
Name                       ips        average  deviation         median         99th %
1 templatable           5.55 K      180.21 μs    ±13.54%      177.63 μs      214.17 μs
all templatables        4.50 K      222.45 μs    ±12.05%      219.67 μs      258.58 μs

Comparison: 
1 templatable           5.55 K
all templatables        4.50 K - 1.23x slower +42.24 μs
```


### ✅ compiler » create_page_entry_files_5

```
Name                                ips        average  deviation         median         99th %
create_page_entry_files/5          1.29      777.20 ms     ±1.23%      772.80 ms      795.52 ms
```


### ✅ compiler » create_runtime_entry_file_4

```
Name                                  ips        average  deviation         median         99th %
create_runtime_entry_file/4         26.98       37.07 ms     ±8.57%       36.71 ms       52.29 ms
```


### ✅ compiler » diff_module_digest_plts_2

```
Name                                         ips        average  deviation         median         99th %
100% modules removed                      4.40 K      227.41 μs    ±12.13%      223.45 μs      286.99 μs
100% modules added                        3.41 K      293.27 μs     ±9.32%      286.15 μs      408.39 μs
33% added, 33% removed, 34% edited        2.78 K      360.04 μs     ±7.40%      359.07 μs      455.62 μs
no module changes                         1.82 K      548.63 μs     ±3.12%      543.97 μs      614.68 μs
3 added, 3 removed, 3 edited              1.75 K      570.17 μs     ±4.18%      565.01 μs      676.39 μs
1 module added                            1.75 K      570.52 μs     ±4.12%      565.25 μs      647.78 μs
1% added, 1% removed, 1% edited           1.73 K      579.57 μs     ±4.28%      576.54 μs      673.40 μs
1 added, 1 removed, 1 edited              1.71 K      584.45 μs     ±3.42%      583.79 μs      651.83 μs
10 added, 10 removed, 10 edited           1.71 K      586.07 μs     ±4.35%      579.54 μs      683.79 μs
100% modules edited                       1.70 K      586.61 μs     ±7.45%      566.64 μs      725.36 μs
1 module removed                          1.69 K      590.16 μs     ±3.35%      588.21 μs      658.07 μs
1 module edited                           1.67 K      598.96 μs     ±6.75%      588.50 μs      742.05 μs

Comparison: 
100% modules removed                      4.40 K
100% modules added                        3.41 K - 1.29x slower +65.86 μs
33% added, 33% removed, 34% edited        2.78 K - 1.58x slower +132.63 μs
no module changes                         1.82 K - 2.41x slower +321.22 μs
3 added, 3 removed, 3 edited              1.75 K - 2.51x slower +342.75 μs
1 module added                            1.75 K - 2.51x slower +343.10 μs
1% added, 1% removed, 1% edited           1.73 K - 2.55x slower +352.15 μs
1 added, 1 removed, 1 edited              1.71 K - 2.57x slower +357.04 μs
10 added, 10 removed, 10 edited           1.71 K - 2.58x slower +358.65 μs
100% modules edited                       1.70 K - 2.58x slower +359.19 μs
1 module removed                          1.69 K - 2.60x slower +362.75 μs
1 module edited                           1.67 K - 2.63x slower +371.54 μs
```


### ✅ compiler » maybe_install_js_deps_2

```
Name                 ips        average  deviation         median         99th %
no install        7.90 K      0.00013 s    ±20.90%      0.00012 s      0.00026 s
do install     0.00010 K        10.15 s     ±0.00%        10.15 s        10.15 s

Comparison: 
no install        7.90 K
do install     0.00010 K - 80163.17x slower +10.15 s
```


### ✅ compiler » maybe_load_call_graph_1

```
Name              ips        average  deviation         median         99th %
no load      205.21 K     0.00487 ms   ±143.61%     0.00467 ms     0.00796 ms
do load      0.0136 K       73.67 ms     ±1.77%       73.28 ms       78.38 ms

Comparison: 
no load      205.21 K
do load      0.0136 K - 15117.71x slower +73.66 ms
```


### ✅ compiler » maybe_load_ir_plt_1

```
Name              ips        average  deviation         median         99th %
no load      108.75 K     0.00920 ms    ±57.60%     0.00892 ms      0.0136 ms
do load     0.00195 K      511.81 ms     ±1.52%      508.29 ms      527.13 ms

Comparison: 
no load      108.75 K
do load     0.00195 K - 55657.33x slower +511.81 ms
```


### ✅ compiler » maybe_load_module_digest_plt_1

```
Name              ips        average  deviation         median         99th %
no load      114.31 K        8.75 μs    ±55.10%        8.50 μs       13.25 μs
do load        2.15 K      465.83 μs     ±3.95%      465.38 μs      516.46 μs

Comparison: 
no load      114.31 K
do load        2.15 K - 53.25x slower +457.09 μs
```


### ✅ compiler » validate_page_modules_1

```
Name                              ips        average  deviation         median         99th %
validate_page_modules/1      123.71 K        8.08 μs    ±94.10%           8 μs        9.13 μs
```


### ✅ mix » tasks » compile » hologram

```
Name                ips        average  deviation         median         99th %
has cache       37.60 K       26.60 μs    ±32.65%       26.38 μs       56.88 μs
no cache        30.33 K       32.97 μs    ±23.57%       30.92 μs       54.07 μs

Comparison: 
has cache       37.60 K
no cache        30.33 K - 1.24x slower +6.37 μs
```


### ✅ reflection » elixir_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            29.28 M       34.15 ns    ±53.63%          42 ns          42 ns
is Erlang module       12.05 M       83.00 ns ±10859.93%          42 ns          84 ns
is atom                11.95 M       83.66 ns ±11251.45%          42 ns          84 ns
is Elixir module        9.32 M      107.29 ns  ±6746.04%          83 ns         125 ns

Comparison: 
is not atom            29.28 M
is Erlang module       12.05 M - 2.43x slower +48.85 ns
is atom                11.95 M - 2.45x slower +49.51 ns
is Elixir module        9.32 M - 3.14x slower +73.14 ns
```


### ✅ reflection » erlang_module_1

```
Name                       ips        average  deviation         median         99th %
is not atom            29.63 M       33.75 ns   ±133.24%          42 ns          42 ns
is Elixir module       17.37 M       57.59 ns  ±7352.83%          42 ns          84 ns
is Erlang module       15.88 M       62.95 ns  ±7093.72%          42 ns          84 ns
is atom               0.0707 M    14136.20 ns    ±59.00%       12375 ns       30541 ns

Comparison: 
is not atom            29.63 M
is Elixir module       17.37 M - 1.71x slower +23.84 ns
is Erlang module       15.88 M - 1.87x slower +29.21 ns
is atom               0.0707 M - 418.87x slower +14102.45 ns
```


### ✅ reflection » has_function_3

```
Name                      ips        average  deviation         median         99th %
has_function?/3       15.69 M       63.73 ns  ±9657.04%          42 ns          84 ns
```


### ✅ reflection » has_struct_1

```
Name                    ips        average  deviation         median         99th %
has_struct?/1       12.63 M       79.15 ns  ±5923.47%          83 ns          84 ns
```


### ✅ reflection » list_elixir_modules_0

```
Name                            ips        average  deviation         median         99th %
list_elixir_modules/0         57.55       17.38 ms     ±7.35%       17.37 ms       20.46 ms
```


### ✅ reflection » list_pages_0

```
Name                   ips        average  deviation         median         99th %
list_pages/0         54.64       18.30 ms     ±6.63%       18.26 ms       20.89 ms
```


### ✅ reflection » list_protocol_implementations_1

```
Name                                      ips        average  deviation         median         99th %
list_protocol_implementations/1        221.01        4.52 ms    ±17.38%        4.27 ms        6.30 ms
```


### ✅ reflection » module_1

```
Name                       ips        average  deviation         median         99th %
is not atom           258.42 M        3.87 ns   ±725.92%        3.75 ns           5 ns
is Elixir module       21.77 M       45.93 ns  ±1818.56%          42 ns          42 ns
is Erlang module       21.60 M       46.29 ns  ±1842.95%          42 ns          42 ns
is atom               0.0669 M    14952.24 ns    ±58.28%       12375 ns       30500 ns

Comparison: 
is not atom           258.42 M
is Elixir module       21.77 M - 11.87x slower +42.06 ns
is Erlang module       21.60 M - 11.96x slower +42.42 ns
is atom               0.0669 M - 3863.98x slower +14948.37 ns
```

